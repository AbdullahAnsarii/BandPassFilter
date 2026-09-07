# FIR band-pass filter in Verilog HDL -- simulation and plots.
#
#   make sim     run both self-checking test benches   (needs Icarus Verilog)
#   make plot    regenerate docs/response.svg          (needs Python 3 only)
#   make lint    syntax and width check on all sources
#   make clean   remove build products
#
# Install Icarus Verilog:
#   macOS          brew install icarus-verilog
#   Debian/Ubuntu  sudo apt install iverilog
#   Windows        https://bleyer.org/icarus/

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
BUILD    ?= build
IFLAGS    = -g2005 -Wall

.PHONY: all sim sim-bandpass sim-firbandpass plot lint clean

all: sim

sim: sim-bandpass sim-firbandpass

sim-bandpass: $(BUILD)/tb_bandpass.vvp
	@$(VVP) $<

sim-firbandpass: $(BUILD)/tb_firbandpass.vvp
	@$(VVP) $<

$(BUILD)/tb_bandpass.vvp: bandpass.v tb_bandpass.v | $(BUILD)
	@$(IVERILOG) $(IFLAGS) -o $@ $^

$(BUILD)/tb_firbandpass.vvp: firbandpass.v tb_firbandpass.v | $(BUILD)
	@$(IVERILOG) $(IFLAGS) -o $@ $^

$(BUILD):
	@mkdir -p $(BUILD)

plot:
	@$(PYTHON) tools/plot_response.py

lint: | $(BUILD)
	@$(IVERILOG) $(IFLAGS) -o $(BUILD)/lint_bandpass.vvp bandpass.v tb_bandpass.v
	@$(IVERILOG) $(IFLAGS) -o $(BUILD)/lint_firbandpass.vvp firbandpass.v tb_firbandpass.v
	@echo "lint: no errors"

clean:
	@rm -rf $(BUILD)
