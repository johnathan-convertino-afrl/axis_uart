//******************************************************************************
/// @FILE    axis_uart_tx.v
/// @AUTHOR  JAY CONVERTINO
/// @DATE    2021.06.24
/// @BRIEF   AXIS UART
/// @DETAILS AXI streaming to UART transmitter
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

//UART
module axis_uart_tx #(
    parameter PARITY_ENA  = 0,
    parameter PARITY_TYPE = 1,
    parameter STOP_BITS   = 1,
    parameter DATA_BITS   = 8,
    parameter DELAY       = 0
  ) 
  (
    //clock and reset
    input aclk,
    input arstn,
    //slave input
    (* mark_debug = "true", keep = "true" *)input   [DATA_BITS-1:0] s_axis_tdata,
    (* mark_debug = "true", keep = "true" *)input                   s_axis_tvalid,
    (* mark_debug = "true", keep = "true" *)output                  s_axis_tready,
    //uart
    input           uart_clk,
    input           uart_rstn,
    (* mark_debug = "true", keep = "true" *)input           uart_ena,
    (* mark_debug = "true", keep = "true" *)output          txd
  );
  
  `include "util_helper_math.vh"
  
  //start bit size... :)
  localparam integer start_bit = 1;
  //bits per transmission
  localparam integer bits_per_trans = start_bit + DATA_BITS + PARITY_ENA + STOP_BITS;
  //states
  // data capture
  localparam data_cap     = 3'd1;
  // parity generator
  localparam parity_gen   = 3'd2;
  // command processor
  localparam process      = 3'd3;
  // transmit data
  localparam trans        = 3'd4;
  // someone made a whoops
  localparam error        = 3'd0;

  //data reg
  (* mark_debug = "true", keep = "true" *)reg [bits_per_trans-1:0]reg_data;
  //parity bit storage
  (* mark_debug = "true", keep = "true" *)reg parity_bit;
  //state machine
  (* mark_debug = "true", keep = "true" *)reg [2:0]  state = error;
  //incoming data to transmit
  (* mark_debug = "true", keep = "true" *)reg [DATA_BITS-1:0] data;
  //counters
  (* mark_debug = "true", keep = "true" *)reg [clogb2(bits_per_trans)-1:0]  trans_counter;
  (* mark_debug = "true", keep = "true" *)reg [clogb2(bits_per_trans)-1:0]  prev_trans_counter;
  //transmit done
  (* mark_debug = "true", keep = "true" *)reg trans_fin;
  //Tx 
  (* mark_debug = "true", keep = "true" *)reg reg_txd;

  
  assign s_axis_tready = (state == data_cap ? arstn : 0);
  
  //axis data input
  always @(posedge aclk) begin
    if(arstn == 1'b0) begin
      data <= 0;
    end else begin
      data <= data;
      
      case (state)
        data_cap:
          if(s_axis_tvalid == 1'b1)
            data <= s_axis_tdata;
        trans:
          data <= 0;
      endcase
    end
  end
  
  //data processing
  always @(posedge aclk) begin
    if(arstn == 1'b0) begin
      state       <= error;
      parity_bit  <= 0;
      reg_data    <= 0;
    end else begin
      case (state)
        //capture data from axis interface
        data_cap: begin
          state       <= data_cap;
          reg_data    <= 0;
          parity_bit  <= 0;
          
          if(s_axis_tvalid == 1'b1) begin
            state <= (PARITY_ENA >= 1 ? parity_gen : process);
          end
        end
        //generate parity using reduction operator
        parity_gen: begin
          state <= process;
          
          case (PARITY_TYPE)
            //odd parity
            1:
              reg_data[bits_per_trans-STOP_BITS-1] <= ^data ^ 1'b1;
            //mark parity
            2:
              reg_data[bits_per_trans-STOP_BITS-1] <= 1'b1;
            //space parity
            3:
              reg_data[bits_per_trans-STOP_BITS-1] <= 1'b0;
            //even parity
            default:
              reg_data[bits_per_trans-STOP_BITS-1] <= ^data;
          endcase
            
        end
        //process command data to setup data transmission
        process: begin
          state <= trans;
          
          //insert start bit
          reg_data[start_bit-1:0] <= 1'b0;
          
          //insert stop bits
          reg_data[bits_per_trans-1:bits_per_trans-STOP_BITS] <= {STOP_BITS{1'b1}};
          
          //insert data
          reg_data[bits_per_trans-STOP_BITS-PARITY_ENA-1:bits_per_trans-STOP_BITS-PARITY_ENA-DATA_BITS] <= data;
          
        end
        //transmit data, actually done in data output process below.
        trans: begin
          state <= trans;
          
          if(trans_fin == 1'b1) begin
            state <= data_cap;
          end
        end
        default:
          state <= data_cap;
      endcase
    end
  end
  
  //DELAY output of data
  generate
    if(DELAY > 0) begin
      //DELAY tx data
      reg [DELAY:0] DELAY_data = 0;
      
      assign txd = DELAY_data[DELAY];
      
      always @(posedge uart_clk) begin
        if(uart_rstn == 1'b0) begin
          DELAY_data <= 0;
        end else begin
          DELAY_data <= {DELAY_data[DELAY-1:0], reg_txd};
        end
      end
    end else begin
      assign txd = reg_txd;
    end
  endgenerate
  
  
  //uart data output positive edge
  always @(posedge uart_clk) begin
    if(uart_rstn == 1'b0) begin
      trans_fin           <= 0;
      reg_txd             <= 1;
      trans_counter       <= 0;
      prev_trans_counter  <= 0;
    end else begin
      case (state)
        //once the state machine is in transmisson state, begin data output
        trans: begin
          //on uart enable, send out data.
          if(uart_ena == 1'b1) begin
            reg_txd <= reg_data[trans_counter];
          
            trans_counter <= trans_counter + 1;
            
            prev_trans_counter  <= trans_counter;
          end
            
          if((trans_counter == bits_per_trans-1) && (prev_trans_counter == bits_per_trans-1)) begin
            trans_fin <= 1'b1;
          end
          
          //once bits_per_trans-1 hold counter
          if(trans_counter == bits_per_trans-1) begin
            trans_counter <= bits_per_trans-1;
          end
        end
        default: begin
          //default state of counters and data output.
          reg_txd             <= 1;
          trans_fin           <= 0;
          trans_counter       <= 0;
          prev_trans_counter  <= 0;
        end
        endcase
    end
  end
endmodule
