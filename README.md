# DPLL
A simple SystemVerilog digital phase-locked loop based (roughly) on TI's [SDLA005B](http://www.ti.com/lit/an/sdla005b/sdla005b.pdf) application note. The design includes a SystemVerilog testbench demonstrating a full generator, driver, monitor, and scoreboard testbench environment.

# DUT: DPLL Design Description
## Figure 5 from SDLA005B (page 4) 
![dpll_figure](dpll_figure.png)

Implemented this DPLL which is used  to lock onto a very slow (kHz range) reference signal and run some logic at phase-locked, faster clock. As implemented here, the input sync signal (clk_fin) is running at 390.625 kHz and the main output clock is clk8x_fout (3.125 MHz).
