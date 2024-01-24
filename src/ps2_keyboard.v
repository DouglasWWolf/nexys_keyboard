/*
    PS/2 keyboards send 8-bit scan-codes packaged into 11 bit bytes.
    PS2_DATA is valid on the low-going edge of PS2_CLK
    On most keyboards, PS2_CLK runs at around 10 Khz

    In this module, a "scan_code" is the 8-bit code that we receive from the PS/2
    interface.   A single key-press (or key-release) may generate multiple scan-codes.

    The 9 bit "key_code" this module outputs uniquely represents each key on the keyboard.
    Bit 8 of "key_code" : 0 = Key was pressed, 1 = Key was released

*/

module ps2_keyboard
(
    input clk, resetn,
    input ps2_clk, ps2_data,

    output reg [8:0] key_code,
    output reg       kc_valid
);


// Debounced, synchronous versions of the ps2_clk and ps2_data
wire ps2_clk_db, ps2_data_db;

// These debounce the PS/2 CLK and DATA signals and make their edges 
// synchronous with our system clock
ps2_debounce(clk, resetn, ps2_clk,  ps2_clk_db );
ps2_debounce(clk, resetn, ps2_data, ps2_data_db);

//==============================================================================
// This block reads 11-bit bytes from the debounced PS/2 clock and data lines.
//
// On a PS/2 interface, PS2_DATA is valid on the low-going edge of PS2_CLK
//
// Whenever a scan_code has been completely received, this block generates a 
// high-going edge on sc_valid.
//
// Keep in mind that this block is being driven by PS2_CLK, which means it's 
// running at roughly 10KHz, <not> at our system-clock rate.
//
// The debouncers immediately above ensure that edges of our debounced PS2_CLK 
// are synchronous with our system clock signal "clk"
//==============================================================================
reg[3:0] bit_counter;   // Count bits in the 11-bit bytes
reg[7:0] scan_code;     // Scan code received from the keyboard
reg      sc_valid;      // When this is high, scan_code is valid
//------------------------------------------------------------------------------
always @(negedge ps2_clk_db) begin

    case (bit_counter)
        0:  sc_valid     <= 0; /* Start bit */
        1:  scan_code[0] <= ps2_data_db;
        2:  scan_code[1] <= ps2_data_db;
        3:  scan_code[2] <= ps2_data_db;
        4:  scan_code[3] <= ps2_data_db;
        5:  scan_code[4] <= ps2_data_db;
        6:  scan_code[5] <= ps2_data_db;
        7:  scan_code[6] <= ps2_data_db;
        8:  scan_code[7] <= ps2_data_db;
        9:  sc_valid     <= 1;
        10: sc_valid     <= 0;
    endcase

    // bit_counter must always cycle from 0 thru 10, repeating forever
    if (bit_counter == 10)
        bit_counter <= 0;
    else
        bit_counter <= bit_counter + 1;
end
//==============================================================================



//==============================================================================
// This performs high-going edge detection on "sc_valid"
//==============================================================================
reg[1:0] sc_valid_history;
//------------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0)
        sc_valid_history <= 0;
    else
        sc_valid_history <= {sc_valid_history[0], sc_valid};
end

// This is high for one cycle when a high-going edge is detected
wire sc_valid_edge = (sc_valid_history == 2'b01);
//==============================================================================


//==============================================================================
// This block turns multi-byte scan codes into a single 9-bit key_code
//==============================================================================

// If this is true, the scan-code we're about to receive is an "extended" code
reg sc_extended;

// If this is true, the key represented by the scan-code is being released
// If this is false, the key represented by the scan-code is being pressed
reg sc_released;

// At any given moment, this is the key_code we might emit
wire[8:0] new_key_code = {sc_released, sc_extended, scan_code[6:0]};
//------------------------------------------------------------------------------
always @(posedge clk) begin
    
    // This will strobe high for a single clock cycle
    kc_valid <= 0;
    
    if (resetn == 0) begin
        sc_extended <= 0;
        sc_released <= 0;
        key_code    <= 0;
    end 

    // If we receive a scan-code from the PS/2 interface...
    else if (sc_valid_edge) begin

        // If we receive scan-code F0, a key is being released
        if (scan_code == 8'hF0)
            sc_released <= 1;
        
        // If we recieve scan-code E0, this is an "extended" key
        else if (scan_code == 8'hE0)
            sc_extended <= 1;
        
        // Any other value represents the key being pressed or released
        else begin
            if (key_code != new_key_code) begin
                key_code <= new_key_code;
                kc_valid <= 1;
            end
            sc_extended <= 0;
            sc_released <= 0;
        end

    end
end
//==============================================================================


endmodule
