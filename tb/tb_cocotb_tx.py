#******************************************************************************
# file:    tb_cocotb.py
#
# author:  JAY CONVERTINO
#
# date:    2024/12/09
#
# about:   Brief
# Cocotb test bench
#
# license: License MIT
# Copyright 2024 Jay Convertino
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
#
#******************************************************************************

import random
import itertools

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer, Event
from cocotb.binary import BinaryValue
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamMonitor, AxiStreamFrame
from cocotbext.uart import UartSource, UartSink

# Function: random_bool
# Return a infinte cycle of random bools
#
# Returns: List
def random_bool():
  temp = []

  for x in range(0, 256):
    temp.append(bool(random.getrandbits(1)))

  return itertools.cycle(temp)

# Function: start_clock
# Start the simulation clock generator.
#
# Parameters:
#   dut - Device under test passed from cocotb test function
def start_clock(dut):
  # axis clock
  cocotb.start_soon(Clock(dut.aclk, 2, units="ns").start())
  # baud clock
  cocotb.start_soon(Clock(dut.uart_clk, 8681, units="ns").start())

# Function: reset_dut
# Cocotb coroutine for resets, used with await to make sure system is reset.
async def reset_dut(dut):
  dut.arstn.value = 0
  dut.uart_rstn.value = 0
  await Timer(20, units="us")
  dut.arstn.value = 1
  dut.uart_rstn.value = 1

# Function: single_word
# Coroutine that is identified as a test routine. This routine tests for writing a single word, and
# then reading a single word.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def single_word(dut):

    start_clock(dut)

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.aclk, dut.arstn, False)

    uart_sink = UartSink(dut.txd, baud=115200, bits=dut.DATA_BITS.value, stop_bits=dut.STOP_BITS.value)

    await reset_dut(dut)

    dut.uart_ena.value = 1

    for x in range(0, 256):
        data = x.to_bytes(length = 1, byteorder='little') * int(dut.BUS_WIDTH.value)
        tx_frame = AxiStreamFrame(data, tx_complete=Event())

        await axis_source.send(tx_frame)
        await tx_frame.tx_complete.wait()

        uart_data = await uart_sink.read()

        assert uart_data == tx_frame.tdata, "Input tdata does not match output"

    await RisingEdge(dut.uart_clk)

    await RisingEdge(dut.uart_clk)

# Function: in_reset
# Coroutine that is identified as a test routine. This routine tests if device stays
# in unready state when in reset.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def in_reset(dut):

    start_clock(dut)

    dut.arstn.value = 0

    dut.uart_rstn.value = 0

    await Timer(10, units="ns")

    assert dut.s_axis_tready.value.integer == 0, "tready is 1!"

# Function: no_clock
# Coroutine that is identified as a test routine. This routine tests if no ready when clock is lost
# and device is left in reset.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def no_clock(dut):

    dut.arstn.value = 0

    dut.uart_rstn.value = 0

    dut.aclk.value = 0

    dut.uart_clk = 0

    await Timer(5, units="ns")

    assert dut.s_axis_tready.value.integer == 0, "tready is 1!"
