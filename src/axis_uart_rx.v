//******************************************************************************
/// @FILE    axis_uart_rx.v
/// @AUTHOR  JAY CONVERTINO
/// @DATE    2021.06.24
/// @BRIEF   AXIS UART RX CORE
///
/// @LICENSE MIT
///  Copyright 2021 Jay Convertino
///
///  Permission is hereby granted, free of charge, to any person obtaining a copy
///  of this software and associated documentation files (the "Software"), to 
///  deal in the Software without restriction, including without limitation the
///  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or 
///  sell copies of the Software, and to permit persons to whom the Software is 
///  furnished to do so, subject to the following conditions:
///
///  The above copyright notice and this permission notice shall be included in 
///  all copies or substantial portions of the Software.
///
///  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
///  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
///  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
///  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
///  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
///  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
///  IN THE SOFTWARE.
//******************************************************************************

`timescale 1ns/100ps

//uart
module axis_uart_rx #(
    parameter PARITY_ENA  = 0,
    parameter PARITY_TYPE = 0,
    parameter STOP_BITS   = 1,
    parameter DATA_BITS   = 8,
    parameter DELAY       = 0
  ) 
  (
    //clock and reset
    input aclk,
    input arstn,
    //error states
    output parity_err,
    output frame_err,
    //master output
    (* mark_debug = "true", keep = "true" *)output  reg[DATA_BITS-1:0]  m_axis_tdata,
    (* mark_debug = "true", keep = "true" *)output  reg                 m_axis_tvalid,
    (* mark_debug = "true", keep = "true" *)input                       m_axis_tready,
    //uart input
    input         uart_clk,
    input         uart_rstn,
    input         uart_ena,
    output  reg   uart_hold,
    input         rxd
  );
  
  `include "util_helper_math.vh"
  
  //start bit size... :)
  localparam integer start_bit = 1;
  //bits per transmission
  localparam integer bits_per_trans = start_bit + DATA_BITS + PARITY_ENA + STOP_BITS;
  //states
  // data capture
  localparam data_cap     = 3'd1;
  // reduce data
  localparam data_reduce  = 3'd2;
  // parity generator
  localparam parity_gen   = 3'd3;
  // transmit data
  localparam trans        = 3'd4;
  // someone made a whoops
  localparam error        = 0;
  //uart_states
  localparam start_wait   = 2'd1;
  localparam data_at_baud = 2'd3;
  
  //data reg
  (* mark_debug = "true", keep = "true" *)reg [bits_per_trans-1:0]reg_data;
  //parity bit storage
  (* mark_debug = "true", keep = "true" *)reg parity_bit;
  //parity error storage
  (* mark_debug = "true", keep = "true" *)reg r_parity_err;
  (* mark_debug = "true", keep = "true" *)reg r_frame_err;
  //state machine
  (* mark_debug = "true", keep = "true" *)reg [2:0]  state = error;
  (* mark_debug = "true", keep = "true" *)reg [1:0]  uart_state = error;
  //data to transmit
  (* mark_debug = "true", keep = "true" *)reg [DATA_BITS-1:0] data;
  //counters
  (* mark_debug = "true", keep = "true" *)reg [clogb2(bits_per_trans)-1:0]  trans_counter;
  (* mark_debug = "true", keep = "true" *)reg [clogb2(bits_per_trans)-1:0]  prev_trans_counter;
  //previous states
  (* mark_debug = "true", keep = "true" *)reg p_rxd;
  //transmit done
  (* mark_debug = "true", keep = "true" *)reg trans_fin;
  //wire_rxd
  wire wire_rxd;

  assign parity_err = r_parity_err;
  assign frame_err  = r_frame_err;
  
  //axis data output
  always @(posedge aclk) begin
    if(arstn == 1'b0) begin
      m_axis_tdata  <= 0;
      m_axis_tvalid <= 0;
    end else begin
      m_axis_tdata <= m_axis_tdata;
      m_axis_tvalid<= m_axis_tvalid;
      case (state)
        //once the state machine is in transmisson state, begin data output
        trans: begin
          m_axis_tdata  <= data;
          m_axis_tvalid <= 1'b1;
        end
        //are we ready kids???? EYYY EYYY CAPTIAN....OHHHHH WHO LIVES IN A PINEAPPLE UNDER THE SEA.
        //...*cough* if we are ready, the data was captured. 0 it out to avoid duplicates.
        default: begin
          if(m_axis_tready == 1'b1) begin
            m_axis_tdata  <= 0;
            m_axis_tvalid <= 0;
          end
        end
        endcase
    end
  end
            
  //data processing
  always @(posedge aclk) begin
    if(arstn == 1'b0) begin
      state           <= error;
      data            <= 0;
      parity_bit      <= 0;
      r_parity_err    <= 0;
      r_frame_err     <= 0;
    end else begin
      case (state)
        //capture data from interface (rx input below)
        data_cap: begin
          state         <= data_cap;
          data          <= 0;
          parity_bit    <= 0;
          
          //once we hit trans_fin, we can goto data combine.
          if(trans_fin == 1'b1) begin
            state <= data_reduce;
          end
        end
        data_reduce: begin
          state <= (PARITY_ENA >= 1'b1 ? parity_gen : trans);
          
          data <= reg_data[start_bit+DATA_BITS-1:start_bit];
          
          parity_bit <= reg_data[bits_per_trans-STOP_BITS-1];

          //pull stop bit, if it is zero, frame error.
          r_frame_err <= ~reg_data[bits_per_trans-1];
        end
        //compare to parity bit of incomming data and store in command
        parity_gen: begin
          state <= trans;
          
          r_parity_err <= 1'b0;

          //check if parity matches, if not do not output data.
          case (PARITY_TYPE)
            //odd parity
            1:
              if(^data ^ 1'b1 ^ parity_bit)
              begin
                state <= data_cap;
                r_parity_err <= 1'b1;
              end
            //mark parity
            2:
              if(parity_bit != 1'b1)
              begin
                state <= data_cap;
                r_parity_err <= 1'b1;
              end
            //space parity
            3:
              if(parity_bit != 1'b0)
              begin
                state <= data_cap;
                r_parity_err <= 1'b1;
              end
            //even parity
            default:
              if(^data ^ parity_bit)
              begin
                state <= data_cap;
                r_parity_err <= 1'b1;
              end
          endcase
        end
        //transmit data, actually done in data output process below.
        trans:
          state <= data_cap;
        //error state, goto data_cap
        default:
          state <= data_cap;
      endcase
    end
  end
  
  //DELAY input of data
  generate
    if(DELAY > 0) begin
      //DELAYs
      reg [DELAY:0] DELAY_rx;
      
      assign wire_rxd = DELAY_rx[DELAY];
      
      always @(posedge uart_clk) begin
        if(uart_rstn == 1'b0) begin
          DELAY_rx <= 0;
        end else begin
          DELAY_rx <= {DELAY_rx[DELAY-1:0], rxd};
        end
      end
    end else begin
      assign wire_rxd = rxd;
    end
  endgenerate
  
  //rxd data input posedge
  always @(posedge uart_clk) begin
    if(uart_rstn == 1'b0) begin
      reg_data            <= 0;
      uart_state          <= error;
      p_rxd               <= 1;
      trans_counter       <= 0;
      prev_trans_counter  <= 0;
      trans_fin           <= 0;
      uart_hold           <= 1;
    end else begin
      p_rxd <= wire_rxd;
      
      case (state)
        //once the state machine is in data caputre state, begin data capture when a diff in the line is sampled.
        data_cap: begin
          case (uart_state)
            //wait for sync bit (start) to begin capture of data at baud rate
            start_wait: begin
              uart_state <= start_wait;
              
              //falling edge of wire_rxd is start bit (1 to 0).
              if((p_rxd == 1'b1) && (wire_rxd == 1'b0)) begin
                uart_state <= data_at_baud;
                uart_hold  <= 1'b0;
              end
            end
            //once sync'd, caputre data at baud rate
            data_at_baud: begin
              uart_state <= data_at_baud;
              uart_hold  <= 1'b0;
              
              //on uart enable, capture data... DELAY added if need be.
              if(uart_ena == 1'b1) begin
                reg_data[trans_counter] <= wire_rxd;
            
                trans_counter <= trans_counter + 1;
                
                prev_trans_counter <= trans_counter;
              end
              
              //once we hit bits_per_trans-1, we can goto data combine.
              if((trans_counter == bits_per_trans-1) && (prev_trans_counter == bits_per_trans-1)) begin
                trans_fin <= 1'b1;
              end
              
              //once bits_per_trans-1 hold counter
              if(trans_counter == bits_per_trans-1) begin
                trans_counter <= bits_per_trans-1;
              end
            end
            default: begin
              uart_state  <= start_wait;
              uart_hold   <= 1'b1;
            end
          endcase
        end
        trans: begin
          reg_data <= 0;
        end
        //default state of counter
        default: begin
          uart_state          <= start_wait;
          trans_fin           <= 0;
          trans_counter       <= 0;
          prev_trans_counter  <= 0;
        end
      endcase
    end
  end
endmodule
