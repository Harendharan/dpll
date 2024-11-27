import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.result import TestFailure
import math

class Transaction:
	def __init__(self, fin_frequency=390625, fout_frequency=0, fout_phase=0, fout8x_frequency=0):
    	self.fin_frequency = fin_frequency
    	self.fout_frequency = fout_frequency
    	self.fout_phase = fout_phase
    	self.fout8x_frequency = fout8x_frequency

	def display(self, tag):
    	print(f"[{tag}] fin: {self.fin_frequency} Hz, fout: {self.fout_frequency} Hz, "
          	f"phase: {self.fout_phase} degrees, fout8x: {self.fout8x_frequency} Hz")

class Generator:
	def __init__(self, count, g2d_queue):
    	self.count = count
    	self.g2d_queue = g2d_queue

	async def run(self):
    	for _ in range(self.count):
        	trn = Transaction(fin_frequency=390625)
        	self.g2d_queue.append(trn)
        	trn.display("GEN")
        	await Timer(1, units='ns')

class Driver:
	def __init__(self, dut, g2d_queue, d2m_queue):
    	self.dut = dut
    	self.g2d_queue = g2d_queue
    	self.d2m_queue = d2m_queue

	async def reset(self):
    	self.dut.reset.value = 1
    	self.dut.clk_fin.value = 0
    	for _ in range(5):
        	await RisingEdge(self.dut.clk)
    	self.dut.reset.value = 0
    	print("[DRV] RESET DONE")

	async def run(self):
    	while self.g2d_queue:
        	trn = self.g2d_queue.pop(0)
        	self.d2m_queue.append(trn)  # Send to monitor via mailbox
        	trn.display("DRV")

        	fin_period_ns = int((1 / trn.fin_frequency) * 1e9)
        	print(f"[DRV] fin_period: {fin_period_ns} ns")

        	for _ in range(500):  # Wait ~1ms for PLL to settle
            	self.dut.clk_fin.value = 0
            	await Timer(fin_period_ns // 2, units='ns')
            	self.dut.clk_fin.value = 1
            	await Timer(fin_period_ns // 2, units='ns')

class Monitor:
	def __init__(self, dut, d2m_queue, m2s_queue):
    	self.dut = dut
    	self.d2m_queue = d2m_queue
    	self.m2s_queue = m2s_queue

	async def run(self):
    	while self.d2m_queue:
        	trn = self.d2m_queue.pop(0)
        	trn.fout_frequency = await self.check_frequency(self.dut.clk_fout)
        	trn.fout8x_frequency = await self.check_frequency(self.dut.clk8x_fout)
        	trn.fout_phase = await self.check_phase(self.dut.clk_fin, self.dut.clk_fout)
        	self.m2s_queue.append(trn)

	async def check_frequency(self, signal):
    	periods = []
    	for _ in range(10):
        	await RisingEdge(signal)
        	t1 = self.dut._log_time
        	await RisingEdge(signal)
        	t2 = self.dut._log_time
        	periods.append(t2 - t1)
    	avg_period = sum(periods) / len(periods)
    	return int(1e9 / avg_period)

	async def check_phase(self, ref_signal, test_signal):
    	await RisingEdge(ref_signal)
    	t_ref = self.dut._log_time
    	await RisingEdge(test_signal)
    	t_test = self.dut._log_time
    	phase = ((t_test - t_ref) * 360) / (1 / 390625 * 1e9)
    	return int(phase)

class Scoreboard:
	def __init__(self, m2s_queue):
    	self.m2s_queue = m2s_queue
    	self.expected_fout_frequency = 390625
    	self.expected_fout8x_frequency = 8 * self.expected_fout_frequency

	async def run(self):
    	while self.m2s_queue:
        	trn = self.m2s_queue.pop(0)
        	trn.display("SB")
        	if trn.fout_frequency != self.expected_fout_frequency:
            	raise TestFailure(f"Frequency mismatch! Expected {self.expected_fout_frequency}, got {trn.fout_frequency}")
        	if trn.fout8x_frequency != self.expected_fout8x_frequency:
            	raise TestFailure(f"8x Frequency mismatch! Expected {self.expected_fout8x_frequency}, got {trn.fout8x_frequency}")

@cocotb.test()
async def dpll_tb(dut):
	"""Cocotb testbench for the dpll module."""
	clock = Clock(dut.clk, 10, units="ns")  # 100 MHz clock
	cocotb.start_soon(clock.start())

	g2d_queue = []
	d2m_queue = []
	m2s_queue = []

	gen = Generator(count=5, g2d_queue=g2d_queue)
	drv = Driver(dut, g2d_queue, d2m_queue)
	mon = Monitor(dut, d2m_queue, m2s_queue)
	sb = Scoreboard(m2s_queue)

	await drv.reset()
	cocotb.start_soon(gen.run())
	cocotb.start_soon(drv.run())
	cocotb.start_soon(mon.run())
	await sb.run()



