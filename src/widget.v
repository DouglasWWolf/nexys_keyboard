module widget
(
    input       clk, resetn,
    input [8:0] key_code,
    input       kc_valid,
    input       button,

    output reg [15:0] key_count,
    output reg [31:0] display,
    output     [ 7:0] digit_enable
);

assign digit_enable = (key_code[8]) ? 3'b111 : 3'b011;

always @(posedge clk) begin

    if (resetn == 0 || button) begin
        key_count <= 0;
    end

    else if (kc_valid) begin
        display   <= key_code;
        key_count <= key_count + 1;
    end

end


endmodule
