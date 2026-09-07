// Self-checking test bench for basicfir (firbandpass.v).
//
// Run with Icarus Verilog:  make sim   (or see the Makefile)
//
// This replaces the stored-vector approach of the generated firbandpass_tb.v,
// whose golden data was produced from the original sfix8_En32 output
// specification and therefore contains only 8'h7f, 8'h80 and 8'h00 -- it
// passes whether or not the filter works. Here the design is compared against
// an independent reference model built from the filter specification:
//
//   product[k] = floor(x[n-k] * h[k] / 2**7)      (sfix16_En17, round to floor)
//   data_out   = sum(product[k]) * 8              (sfix20_En20)
//
// The accumulator cannot saturate: the input range is +/-0.25 and sum(|h|) is
// 1.5869, so |output| <= 0.397 against an accumulator range of +/-0.5.
`timescale 1 ns / 1 ns

module tb_firbandpass;

  localparam integer TAPS = 51;

  reg                clk = 1'b0;
  reg                reset = 1'b1;
  reg                clk_enable = 1'b0;
  reg  signed [7:0]  data_in = 8'sd0;
  wire signed [19:0] data_out;

  reg  signed [7:0]  hist [0:63];
  reg  signed [13:0] h    [0:TAPS-1];
  reg  signed [63:0] expected, prod;

  integer i, k, n, errors, checks;
  reg checking;

  basicfir dut (
    .clk        (clk),
    .clk_enable (clk_enable),
    .reset      (reset),
    .data_in    (data_in),
    .data_out   (data_out)
  );

  always #5 clk = ~clk;

  // Coefficients, copied from the parameters in firbandpass.v.
  initial begin
    h[0] = 13; h[1] = -11; h[2] = -90; h[3] = -57; h[4] = 169; h[5] = 212;
    h[6] = -186; h[7] = -416; h[8] = 81; h[9] = 525; h[10] = 73; h[11] = -412;
    h[12] = -46; h[13] = 133; h[14] = -415; h[15] = -1; h[16] = 1338; h[17] = 438;
    h[18] = -2369; h[19] = -1655; h[20] = 2894; h[21] = 3387; h[22] = -2418; h[23] = -4936;
    h[24] = 945; h[25] = 5559; h[26] = 945; h[27] = -4936; h[28] = -2418; h[29] = 3387;
    h[30] = 2894; h[31] = -1655; h[32] = -2369; h[33] = 438; h[34] = 1338; h[35] = -1;
    h[36] = -415; h[37] = 133; h[38] = -46; h[39] = -412; h[40] = 73; h[41] = 525;
    h[42] = 81; h[43] = -416; h[44] = -186; h[45] = 212; h[46] = 169; h[47] = -57;
    h[48] = -90; h[49] = -11; h[50] = 13;
  end

  task apply_sample;
    input signed [7:0] x;
    begin
      @(negedge clk);
      data_in = x;
      for (i = 63; i > 0; i = i - 1) hist[i] = hist[i-1];
      hist[0] = x;
      @(posedge clk);
      #1;
      if (checking) begin
        expected = 64'sd0;
        for (k = 0; k < TAPS; k = k + 1) begin
          // Arithmetic shift right by 7 == floor division, matching the RTL.
          prod = ($signed(hist[k]) * $signed(h[k])) >>> 7;
          expected = expected + (prod <<< 3);
        end
        checks = checks + 1;
        if (data_out !== expected[19:0]) begin
          errors = errors + 1;
          if (errors <= 10)
            $display("  FAIL sample %0d: data_out = %0d, expected %0d",
                     n, $signed(data_out), $signed(expected[19:0]));
        end
      end
    end
  endtask

  task start_case;
    input [8*64:1] name;
    begin
      $display("%0s", name);
      checking = 1'b0;
      for (i = 0; i < 64; i = i + 1) hist[i] = 8'sd0;
      for (n = 0; n < TAPS + 2; n = n + 1) apply_sample(8'sd0);
      checking = 1'b1;
    end
  endtask

  // Test 1: the impulse response must be the coefficients, floor-scaled.
  task test_impulse;
    integer seen, expect_k;
    begin
      start_case("test 1: impulse response == coefficients");
      apply_sample(8'sd64);
      seen = 0;
      for (n = 0; n < TAPS; n = n + 1) begin
        expect_k = (((64 * h[seen]) >>> 7) <<< 3);
        if ($signed(data_out) !== expect_k) begin
          errors = errors + 1;
          if (errors <= 10)
            $display("  FAIL h[%0d]: got %0d, expected %0d",
                     seen, $signed(data_out), expect_k);
        end
        checks = checks + 1;
        seen = seen + 1;
        apply_sample(8'sd0);
      end
    end
  endtask

  // Test 2: the output must carry amplitude, not just a sign. The original
  // sfix8_En32 output collapsed every non-zero value onto +127 / -128.
  task test_not_a_sign_detector;
    integer distinct, j, m;
    reg signed [19:0] seen_vals [0:255];
    reg found;
    begin
      start_case("test 2: output carries amplitude, not just sign");
      distinct = 0;
      for (n = 0; n < 200; n = n + 1) begin
        apply_sample(n % 32 < 16 ? 8'sd40 : -8'sd40);
        found = 1'b0;
        for (j = 0; j < distinct; j = j + 1)
          if (seen_vals[j] === data_out) found = 1'b1;
        if (!found && distinct < 256) begin
          seen_vals[distinct] = data_out;
          distinct = distinct + 1;
        end
      end
      $display("  distinct output values observed: %0d", distinct);
      checks = checks + 1;
      if (distinct <= 3) begin
        errors = errors + 1;
        $display("  FAIL: output takes only %0d distinct values -- it is a sign detector, not a filter",
                 distinct);
      end
    end
  endtask

  task test_full_scale_noise;
    begin
      start_case("test 3: full-scale random input");
      for (n = 0; n < 400; n = n + 1) apply_sample($random);
    end
  endtask

  initial begin
    errors  = 0;
    checks  = 0;
    checking = 1'b0;
    for (i = 0; i < 64; i = i + 1) hist[i] = 8'sd0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
    clk_enable = 1'b1;

    test_impulse();
    test_not_a_sign_detector();
    test_full_scale_noise();

    $display("");
    if (errors == 0)
      $display("PASS  basicfir: %0d checks, 0 mismatches", checks);
    else
      $display("FAIL  basicfir: %0d checks, %0d mismatches", checks, errors);
    $display("");
    if (errors != 0) $stop;
    $finish;
  end

endmodule
