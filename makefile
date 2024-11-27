TOPLEVEL_LANG ?= verilog
SIM ?= icarus
VERILOG_SOURCES = $(shell pwd)/dpll.sv
TOPLEVEL := dpll # Verilog or SystemVerilog TOP file module name
MODULE   := testbench # Python file name


include $(shell cocotb-config --makefiles)/Makefile.sim
