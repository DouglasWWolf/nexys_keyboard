//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2021.1 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
//Date        : Wed Jan 24 14:17:30 2024
//Host        : simtool-5 running 64-bit Ubuntu 20.04.6 LTS
//Command     : generate_target top_level_wrapper.bd
//Design      : top_level_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module top_level_wrapper
   (AN,
    BTNC,
    CLK100MHZ,
    CPU_RESETN,
    LED,
    PS2_CLK,
    PS2_DATA,
    SEG);
  output [7:0]AN;
  input BTNC;
  input CLK100MHZ;
  input CPU_RESETN;
  output [15:0]LED;
  input [0:0]PS2_CLK;
  input [0:0]PS2_DATA;
  output [7:0]SEG;

  wire [7:0]AN;
  wire BTNC;
  wire CLK100MHZ;
  wire CPU_RESETN;
  wire [15:0]LED;
  wire [0:0]PS2_CLK;
  wire [0:0]PS2_DATA;
  wire [7:0]SEG;

  top_level top_level_i
       (.AN(AN),
        .BTNC(BTNC),
        .CLK100MHZ(CLK100MHZ),
        .CPU_RESETN(CPU_RESETN),
        .LED(LED),
        .PS2_CLK(PS2_CLK),
        .PS2_DATA(PS2_DATA),
        .SEG(SEG));
endmodule
