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


module sevenseg_axi_fe #
(
    // 0 = Single, 1 = Split  
    parameter DEFAULT_MODE   = 0,  
    
    // A 1-bit = decimal, a 0-bit = hex
    parameter DEFAULT_FORMAT = 3
)
(

    input         clk, resetn,
    output [31:0] display,
    output [ 2:0] cfg,

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

// 32-bit raw value
reg[31:0] single_raw;

// Raw values for a pair of 16-bit values
reg[15:0] right_raw, left_raw;

// A 0-bit = "Hex", a 1-bit = "Decimal"
reg[1:0] format;

// Display mode: one 8 character field, or two 4 four character fields
localparam MODE_SINGLE = 0;
localparam MODE_SPLIT  = 1;
reg mode;

// Pack the configuration bits into the "cfg" output
assign cfg = {format, mode};

// The displayed output is either a single field or two independent fields
assign display = (mode == MODE_SINGLE) ? single_raw : {left_raw, right_raw};

//==========================================================================
// This state machine handles AXI4-Lite write requests
//
// Drives: ashi_write_state
//         ashi_wresp
//         mode,
//         single_raw, right_raw, left_raw
//         single_bcd, right_bcd, left_bcd
//==========================================================================
always @(posedge clk) begin

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_write_state  <= 0;
        format            <= DEFAULT_FORMAT;
        mode              <= DEFAULT_MODE;
        single_raw        <= 0;
        right_raw         <= 0;
        left_raw          <= 0;

    // If we're not in reset, and a write-request has occured...        
    end else case (ashi_write_state)
        
        0:  if (ashi_write) begin
       
                // Assume for the moment that the result will be OKAY
                ashi_wresp <= OKAY;              
            
                // Examine the register index to determine which register we're writing to
                case (ashi_windx)
               
                    REG_SINGLE:
                        begin
                            mode       <= MODE_SINGLE;
                            single_raw <= ashi_wdata;
                        end

                    REG_RIGHT:
                        begin
                            mode       <= MODE_SPLIT;
                            right_raw  <= ashi_wdata;
                        end

                    REG_LEFT:
                        begin
                            mode       <= MODE_SPLIT;
                            left_raw   <= ashi_wdata;
                        end

                    REG_FORMAT:
                        format         <= ashi_wdata;

                    // Writes to any other register are a decode-error
                    default: ashi_wresp <= DECERR;
                endcase
            end


        // We should never get here.
        1:  ashi_write_state <= 0;

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

