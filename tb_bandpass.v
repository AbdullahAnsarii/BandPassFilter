// Self-checking test bench for bandpass_filter (bandpass.v).
//
// Run with Icarus Verilog:  make sim   (or see the Makefile)
//
// The design is a fully serial FIR: one multiplier, folding factor 9, so one
// input sample is consumed every 9 clocks. Every shift in the datapath is a
// left shift and the accumulator is wide enough to hold sum(|h|), so the
// arithmetic is exact -- filter_out must equal 256 * sum(h[k] * x[n-2-k])
// for every input, with no rounding and no overflow. That is what the
// reference model below computes, in 64-bit integers.
//
// Stimulus deliberately includes the case that overflowed the original
// sfix26_En24 accumulator: a full-scale square wave at the passband centre.
`timescale 1 ns / 1 ns

module tb_bandpass;

  localparam integer TAPS         = 11;
  localparam integer FOLD         = 9;    // clocks per input sample
  localparam integer LATENCY      = 2;    // sample periods from input to output
  localparam integer OUTPUT_SCALE = 256;  // En17*En5 -> En30

  reg                 clk = 1'b0;
  reg                 reset = 1'b1;
  reg                 clk_enable = 1'b0;
  reg  signed [17:0]  filter_in = 18'sd0;
  wire signed [32:0]  filter_out;

  // Reference model state: the last few input samples, newest first.
  reg  signed [17:0]  hist [0:63];
  reg  signed [5:0]   h    [0:TAPS-1];
  reg  signed [63:0]  expected;

  integer i, k, n, errors, checks;
  reg checking;

  bandpass_filter dut (
    .clk        (clk),
    .clk_enable (clk_enable),
    .reset      (reset),
    .filter_in  (filter_in),
    .filter_out (filter_out)
  );

  always #5 clk = ~clk;

  // Coefficients, copied from the parameters in bandpass.v.
  initial begin
    h[0] = -3; h[1] = -8; h[2] = -8; h[3] = 0; h[4] = 11; h[5] = 16; h[6] = 11; h[7] = 0;
    h[8] = -8; h[9] = -8; h[10] = -3;
  end

  // Apply one input sample: drive on the falling edge so the stimulus never
  // races the posedge the DUT samples on, hold it for FOLD clocks, then check.
  task apply_sample;
    input signed [17:0] x;
    begin
      @(negedge clk);
      filter_in = x;
      for (i = 63; i > 0; i = i - 1) hist[i] = hist[i-1];
      hist[0] = x;
      repeat (FOLD) @(posedge clk);
      #1;
      if (checking) begin
        expected = 64'sd0;
        for (k = 0; k < TAPS; k = k + 1)
          expected = expected + $signed(hist[LATENCY + k]) * $signed(h[k]) * OUTPUT_SCALE;
        checks = checks + 1;
        if (filter_out !== expected[32:0]) begin
          errors = errors + 1;
          if (errors <= 10)
            $display("  FAIL sample %0d: filter_out = %0d, expected %0d",
                     n, $signed(filter_out), expected);
        end
      end
    end
  endtask

  task start_case;
    input [8*64:1] name;
    begin
      $display("%0s", name);
      checking = 1'b0;
      // Flush the pipeline with zeros so each case starts from a known state.
      for (i = 0; i < 64; i = i + 1) hist[i] = 18'sd0;
      for (n = 0; n < TAPS + LATENCY + 2; n = n + 1) apply_sample(18'sd0);
      checking = 1'b1;
    end
  endtask

  // Test 1: the impulse response must be the coefficients themselves.
  task test_impulse;
    integer seen, expect_k;
    begin
      start_case("test 1: impulse response == coefficients");
      apply_sample(18'sd65536);                     // 0.5 full scale
      seen = 0;
      for (n = 0; n < TAPS + LATENCY; n = n + 1) begin
        apply_sample(18'sd0);
        if (n >= LATENCY - 1 && seen < TAPS) begin
          expect_k = 65536 * h[seen] * OUTPUT_SCALE;
          if ($signed(filter_out) !== expect_k) begin
            errors = errors + 1;
            $display("  FAIL h[%0d]: got %0d, expected %0d",
                     seen, $signed(filter_out), expect_k);
          end
          checks = checks + 1;
          seen = seen + 1;
        end
      end
    end
  endtask

  // Test 2: the stimulus that wrapped the original 26-bit accumulator.
  task test_square_wave;
    begin
      start_case("test 2: full-scale square wave at the passband centre");
      for (n = 0; n < 200; n = n + 1)
        apply_sample((n % 8) < 4 ? 18'sh1FFFF : -18'sh20000);
    end
  endtask

  task test_full_scale_noise;
    begin
      start_case("test 3: full-scale random input");
      for (n = 0; n < 300; n = n + 1)
        apply_sample($random % 18'sh20000);
    end
  endtask

  // Test 4: the worst case for the accumulator -- the input sign pattern that
  // lines up with the coefficient signs, which reaches sum(|h|) = 2.375.
  task test_worst_case;
    begin
      start_case("test 4: worst-case sign pattern (accumulator hits 2.375)");
      for (n = 0; n < 60; n = n + 1)
        apply_sample(h[(TAPS - 1) - (n % TAPS)] >= 0 ? 18'sh1FFFF : -18'sh20000);
    end
  endtask

  initial begin
    errors  = 0;
    checks  = 0;
    checking = 1'b0;
    for (i = 0; i < 64; i = i + 1) hist[i] = 18'sd0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    clk_enable = 1'b1;

    test_impulse();
    test_square_wave();
    test_full_scale_noise();
    test_worst_case();

    $display("");
    if (errors == 0)
      $display("PASS  bandpass_filter: %0d checks, 0 mismatches", checks);
    else
      $display("FAIL  bandpass_filter: %0d checks, %0d mismatches", checks, errors);
    $display("");
    if (errors != 0) $stop;
    $finish;
  end

endmodule
