//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 16-Dec-23  DWW     1  Initial creation
//====================================================================================

/*
    Register Offset  -- Meaning
    ----------------------------------------------------------------
    0x00                Module version - read only
    0x04                Display a single field -  32-bit value
    0x08                Display two 16-bit fields - this is the right-side field
    0x0C                Display two 16-bit fields - this is the left-side field
    0x10                Format: Bit 0 : 0 = Single/right display is in hex
                                Bit 0 : 1 = Single/right display is in decimal
                                Bit 1 : 0 = Left display is in hex
                                Bit 1 : 1 = Left display is in decimal
*/


module axi_7seg #
(
    // 0 = Single, 1 = Split  
    parameter DEFAULT_MODE   = 0,  
    
    // A 1-bit = decimal, a 0-bit = hex
    parameter DEFAULT_FORMAT = 3
)
(
    input clk, resetn,

    output [31:0] display,

    output [7:0] digit_enable,

    //================== This is an AXI4-Lite slave interface ==================
        
    // "Specify write address"              -- Master --    -- Slave --
    input[31:0]                             S_AXI_AWADDR,   
    input                                   S_AXI_AWVALID,  
    output                                                  S_AXI_AWREADY,
    input[2:0]                              S_AXI_AWPROT,

    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             S_AXI_WDATA,      
    input                                   S_AXI_WVALID,
    input[3:0]                              S_AXI_WSTRB,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[31:0]                             S_AXI_ARADDR,     
    input                                   S_AXI_ARVALID,
    input[2:0]                              S_AXI_ARPROT,     
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    input                                   S_AXI_RREADY
    //==========================================================================
);  

// Any time the register map of this module changes, this number should
// be bumped
localparam MODULE_VERSION = 1;

//=========================  AXI Register Map  =============================
localparam REG_MODULE_REV      = 0;
localparam REG_SINGLE          = 1;
localparam REG_RIGHT           = 2;
localparam REG_LEFT            = 3;
localparam REG_FORMAT          = 4;
//==========================================================================


//==========================================================================
// We'll communicate with the AXI4-Lite Slave core with these signals.
//==========================================================================
// AXI Slave Handler Interface for write requests
wire[31:0]  ashi_windx;     // Input   Write register-index
wire[31:0]  ashi_waddr;     // Input:  Write-address
wire[31:0]  ashi_wdata;     // Input:  Write-data
wire        ashi_write;     // Input:  1 = Handle a write request
reg[1:0]    ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
wire        ashi_widle;     // Output: 1 = Write state machine is idle

// AXI Slave Handler Interface for read requests
wire[31:0]  ashi_rindx;     // Input   Read register-index
wire[31:0]  ashi_raddr;     // Input:  Read-address
wire        ashi_read;      // Input:  1 = Handle a read request
reg[31:0]   ashi_rdata;     // Output: Read data
reg[1:0]    ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
wire        ashi_ridle;     // Output: 1 = Read state machine is idle
//==========================================================================

// The state of the state-machines that handle AXI4-Lite read and AXI4-Lite write
reg ashi_write_state, ashi_read_state;

// The AXI4 slave state machines are idle when in state 0 and their "start" signals are low
assign ashi_widle = (ashi_write == 0) && (ashi_write_state == 0);
assign ashi_ridle = (ashi_read  == 0) && (ashi_read_state  == 0);
   
// These are the valid values for ashi_rresp and ashi_wresp
localparam OKAY   = 0;
localparam SLVERR = 2;
localparam DECERR = 3;

// An AXI slave is gauranteed a minimum of 128 bytes of address space
// (128 bytes is 32 32-bit registers)
localparam ADDR_MASK = 7'h7F;

// 32-bit raw value and its BCD equivalent
reg[31:0] single_raw, single_bcd;

// Digit-enable for a single 32-bit value
reg[ 7:0] single_de;

// Raw and BCD equivalents for a pair of 16-bit values
reg[15:0] right_raw, left_raw, right_bcd, left_bcd;

// Digit-enable for both of the 16-bit values
reg[ 3:0] right_de, left_de;

// A 0-bit = "Hex", a 1-bit = "Decimal"
reg[1:0] format;

// The bit pattern to output depends on the desired format (hex or decimal)
wire[31:0] single_out = (format[0] == 0) ? single_raw : single_bcd;
wire[15:0] right_out  = (format[0] == 0) ? right_raw  : right_bcd;
wire[15:0] left_out   = (format[1] == 0) ? left_raw   : left_bcd;

// Display mode: one 8 character field, or two 4 four character fields
localparam MODE_SINGLE = 0;
localparam MODE_SPLIT  = 1;
reg mode;

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
// Drives: ashi_write_state
//         ashi_wresp
//         dd_input, dd_start
//         mode,
//         single_raw, right_raw, left_raw
//         single_bcd, right_bcd, left_bcd
//==========================================================================
always @(posedge clk) begin

    // This strobes high for only a single cycle at a time
    dd_start <= 0;

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_write_state  <= 0;
        format            <= DEFAULT_FORMAT;
        mode              <= DEFAULT_MODE;
        single_raw        <= 0;
        single_bcd        <= 0;
        right_raw         <= 0;
        right_bcd         <= 0;
        left_raw          <= 0;
        left_bcd          <= 0;

    // If we're not in reset, and a write-request has occured...        
    end else case (ashi_write_state)
        
        0:  if (ashi_write) begin
       
                // Assume for the moment that the result will be OKAY
                ashi_wresp <= OKAY;              
            
                // Examine the register index to determine which register we're writing to
                case (ashi_windx)
               
                    REG_SINGLE:
                        begin
                            mode             <= MODE_SINGLE;
                            single_raw       <= ashi_wdata;
                            dd_input         <= ashi_wdata;
                            dd_start         <= 1;
                            ashi_write_state <= 1;
                        end

                    REG_RIGHT:
                        begin
                            mode             <= MODE_SPLIT;
                            right_raw        <= ashi_wdata;
                            dd_input         <= ashi_wdata;
                            dd_start         <= 1;
                            ashi_write_state <= 1;
                        end

                    REG_LEFT:
                        begin
                            mode             <= MODE_SPLIT;
                            left_raw         <= ashi_wdata;
                            dd_input         <= ashi_wdata;
                            dd_start         <= 1;
                            ashi_write_state <= 1;
                        end

                    REG_FORMAT:
                        format <= ashi_wdata;

                    // Writes to any other register are a decode-error
                    default: ashi_wresp <= DECERR;
                endcase
            end


        // Waits for double-dabble to complete
        1:  if (dd_done) begin
                if (ashi_windx == REG_SINGLE) single_bcd <= dd_output;
                if (ashi_windx == REG_LEFT  ) left_bcd   <= dd_output;
                if (ashi_windx == REG_RIGHT ) right_bcd  <= dd_output;
                ashi_write_state <= 0;
            end

    endcase
end
//==========================================================================





//==========================================================================
// World's simplest state machine for handling AXI4-Lite read requests
//==========================================================================
always @(posedge clk) begin
    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_read_state <= 0;
    
    // If we're not in reset, and a read-request has occured...        
    end else if (ashi_read) begin
   
        // Assume for the moment that the result will be OKAY
        ashi_rresp <= OKAY;              
        
        // Determine which register the user wants to read
        case (ashi_rindx)
            
            // Allow a read from any valid register                
            REG_MODULE_REV:     ashi_rdata <= MODULE_VERSION;
            REG_SINGLE:         ashi_rdata <= single_raw;
            REG_RIGHT:          ashi_rdata <= right_raw;
            REG_LEFT:           ashi_rdata <= left_raw;
            REG_FORMAT:         ashi_rdata <= format;
            
            // Reads of any other register are a decode-error
            default: ashi_rresp <= DECERR;
        endcase
    end
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



//==========================================================================
// This connects us to an AXI4-Lite slave core
//==========================================================================
axi4_lite_slave#(ADDR_MASK) axil_slave
(
    .clk            (clk),
    .resetn         (resetn),
    
    // AXI AW channel 
    .AXI_AWADDR     (S_AXI_AWADDR),
    .AXI_AWVALID    (S_AXI_AWVALID),   
    .AXI_AWREADY    (S_AXI_AWREADY),
    
    // AXI W channel
    .AXI_WDATA      (S_AXI_WDATA),
    .AXI_WVALID     (S_AXI_WVALID),
    .AXI_WSTRB      (S_AXI_WSTRB),
    .AXI_WREADY     (S_AXI_WREADY),

    // AXI B channel
    .AXI_BRESP      (S_AXI_BRESP),
    .AXI_BVALID     (S_AXI_BVALID),
    .AXI_BREADY     (S_AXI_BREADY),

    // AXI AR channel
    .AXI_ARADDR     (S_AXI_ARADDR), 
    .AXI_ARVALID    (S_AXI_ARVALID),
    .AXI_ARREADY    (S_AXI_ARREADY),

    // AXI R channel
    .AXI_RDATA      (S_AXI_RDATA),
    .AXI_RVALID     (S_AXI_RVALID),
    .AXI_RRESP      (S_AXI_RRESP),
    .AXI_RREADY     (S_AXI_RREADY),

    // ASHI write-request registers
    .ASHI_WADDR     (ashi_waddr),
    .ASHI_WINDX     (ashi_windx),
    .ASHI_WDATA     (ashi_wdata),
    .ASHI_WRITE     (ashi_write),
    .ASHI_WRESP     (ashi_wresp),
    .ASHI_WIDLE     (ashi_widle),

    // ASHI read registers
    .ASHI_RADDR     (ashi_raddr),
    .ASHI_RINDX     (ashi_rindx),
    .ASHI_RDATA     (ashi_rdata),
    .ASHI_READ      (ashi_read ),
    .ASHI_RRESP     (ashi_rresp),
    .ASHI_RIDLE     (ashi_ridle)
);
//==========================================================================


endmodule

