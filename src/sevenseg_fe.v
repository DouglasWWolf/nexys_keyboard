//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 23-Jan-24  DWW     1  Initial creation
//====================================================================================

/*

*/


module sevenseg_fe 
(
    input clk, resetn,

    input  [31:0] input_value,
    input  [ 2:0] cfg,

    output [31:0] display,
    output [ 7:0] digit_enable
);  

// Constants to identify which field double-dabble is converting
localparam REG_SINGLE = 1;
localparam REG_RIGHT  = 2;
localparam REG_LEFT   = 4;

// 32-bit raw value and its BCD equivalent
reg[31:0] single_raw, single_bcd;

// Digit-enable for a single 32-bit value
reg[ 7:0] single_de;

// Raw and BCD equivalents for a pair of 16-bit values
reg[15:0] right_raw, left_raw, right_bcd, left_bcd;

// Digit-enable for both of the 16-bit values
reg[ 3:0] right_de, left_de;

// A 0-bit = "Hex", a 1-bit = "Decimal"
wire[1:0] format = cfg[2:1];

// The bit pattern to output depends on the desired format (hex or decimal)
wire[31:0] single_out = (format[0] == 0) ? single_raw : single_bcd;
wire[15:0] right_out  = (format[0] == 0) ? right_raw  : right_bcd;
wire[15:0] left_out   = (format[1] == 0) ? left_raw   : left_bcd;

// Display mode: one 8 character field, or two 4 four character fields
localparam MODE_SINGLE = 0;
localparam MODE_SPLIT  = 1;
wire mode = cfg[0];

// The displayed output is either a single field or two independent fields
assign display = (mode == MODE_SINGLE) ? single_out : {left_out, right_out};

// Determine which digits should be displayed. (Don't display leading zeros)
assign digit_enable = (mode == MODE_SINGLE) ? single_de : {left_de, right_de};

//=============================================================================
// double_dabble - Converts binary to BCD
//=============================================================================
reg [31:0] dd_input;
reg        dd_start;
wire[31:0] dd_output;
wire       dd_done;
double_dabble#(.INPUT_WIDTH(32), .DECIMAL_DIGITS(8))
(
    .clk    (clk),
    .resetn (resetn),
    .BINARY (dd_input),
    .START  (dd_start),
    .BCD    (dd_output),
    .DONE   (dd_done)
);
//=============================================================================


//==========================================================================
// This state machine handles AXI4-Lite write requests
//
// Drives: fsm_state, return_state
//         which
//         dd_input, dd_start
//         single_raw, right_raw, left_raw
//         single_bcd, right_bcd, left_bcd
//==========================================================================
reg[1:0] fsm_state, return_state;
reg[2:0] which;
always @(posedge clk) begin

    // This strobes high for only a single cycle at a time
    dd_start <= 0;

    if (resetn == 0) begin
        fsm_state   <= 0;
        single_raw  <= 0;
        single_bcd  <= 0;
        right_raw   <= 0;
        right_bcd   <= 0;
        left_raw    <= 0;
        left_bcd    <= 0;

    end else case (fsm_state)

        // In state 0, start a dd conversion for either "single" or "right"
        0:  if (mode == MODE_SINGLE) begin
                single_raw   <= input_value;
                dd_input     <= input_value;
                dd_start     <= 1;
                which        <= REG_SINGLE;
                return_state <= 0;
                fsm_state    <= 2;
            end else begin
                right_raw    <= input_value[15:0];
                dd_input     <= input_value[15:0];
                dd_start     <= 1;
                which        <= REG_RIGHT;
                return_state <= 1;
                fsm_state    <= 2;
            end

        // In state 1, start a dd conversion for "left"
        1:  begin
                left_raw     <= input_value[31:16];
                dd_input     <= input_value[31:16];
                dd_start     <= 1;
                which        <= REG_LEFT;
                return_state <= 0;
                fsm_state    <= 2;
            end

        // Here, we're waiting for double-dabble to complete so that
        // we can store the result into the appropriate register
        2:  if (dd_done) begin
                if (which == REG_SINGLE) single_bcd <= dd_output;
                if (which == REG_RIGHT ) right_bcd  <= dd_output;
                if (which == REG_LEFT  ) left_bcd   <= dd_output;
                fsm_state                           <= return_state;
            end

    endcase


end
//==========================================================================



//==========================================================================
// single_de = bitmap of which digits in single_out are significant
//==========================================================================
always @* begin
    if      (single_out[31:04] == 0) single_de = 8'b00000001;
    else if (single_out[31:08] == 0) single_de = 8'b00000011;
    else if (single_out[31:12] == 0) single_de = 8'b00000111;
    else if (single_out[31:16] == 0) single_de = 8'b00001111;
    else if (single_out[31:20] == 0) single_de = 8'b00011111;
    else if (single_out[31:24] == 0) single_de = 8'b00111111;
    else if (single_out[31:28] == 0) single_de = 8'b01111111;
    else                             single_de = 8'b11111111;
end
//==========================================================================


//==========================================================================
// right_de = bitmap of which digits in right_out are significant
//==========================================================================
always @* begin
    if      (right_out[15:04] == 0) right_de = 4'b0001;
    else if (right_out[15:08] == 0) right_de = 4'b0011;
    else if (right_out[15:12] == 0) right_de = 4'b0111;
    else                            right_de = 4'b1111;
end
//==========================================================================


//==========================================================================
// left_de = bitmap of which digits in left_out are significant
//==========================================================================
always @* begin
    if      (left_out[15:04] == 0) left_de = 4'b0001;
    else if (left_out[15:08] == 0) left_de = 4'b0011;
    else if (left_out[15:12] == 0) left_de = 4'b0111;
    else                           left_de = 4'b1111;
end
//==========================================================================



endmodule
