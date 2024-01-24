//======================================================================================================================
// double_dabble() - Implements the classic "double dabble" binary-to-BCD algorithm
//======================================================================================================================
module double_dabble#(parameter INPUT_WIDTH=1,  parameter DECIMAL_DIGITS=1)
(
    input                             clk, resetn,
    input [INPUT_WIDTH-1:0]           BINARY,
    input                             START,
    output reg [DECIMAL_DIGITS*4-1:0] BCD,
    output                            DONE
);

// The number of bits in the BCD output
localparam BCD_BITS = DECIMAL_DIGITS * 4;

// State of the state machine
reg                   fsm_state;

// Current estimate of the BCD value
reg [BCD_BITS-1:0]    bcd;

// Each BCD digit adjusted +3 as neccessary
wire[BCD_BITS-1:0]    next_bcd;

// Holds the bits of the original input value
reg [INPUT_WIDTH-1:0] binary;

// We will perform as many shifts as we have input bits
reg [7:0]             counter;

//=============================================================================
// This block generates "next_bcd" from "bcd".  Each nybble of next_bcd
// is the corresponding nybble in "bcd", plus 3 (if the original was > 4)
//=============================================================================
genvar i;
for (i=0; i<DECIMAL_DIGITS; i=i+1) begin
    assign next_bcd[i*4 +:4] = (bcd[i*4 +:4] > 4) ? bcd[i*4 +:4] + 3 
                                                  : bcd[i*4 +:4];   
end
//=============================================================================


//=============================================================================
// This block implements the classic "double-dabble" binary to BCD conversion
//=============================================================================
always @(posedge clk) begin

    if (resetn == 0)
        fsm_state <= 0;
    else case (fsm_state)

        0:  if (START) begin
                bcd       <= BINARY[INPUT_WIDTH-1];
                binary    <= BINARY << 1;
                counter   <= INPUT_WIDTH-1;
                fsm_state <= 1;
            end

        1:  if (counter) begin
                bcd     <= {next_bcd[BCD_BITS-2:0], binary[INPUT_WIDTH-1]};
                binary  <= binary << 1;
                counter <= counter - 1;
            end else begin
                BCD       <= bcd;
                fsm_state <= 0;
            end

    endcase

end

assign DONE = (START == 0 && fsm_state == 0);
//=============================================================================

endmodule

