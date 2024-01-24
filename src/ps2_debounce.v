module ps2_debounce
(
    input clk, resetn,
    input I,
    output reg O
);

reg[4:0] counter;
reg      previous_I;

always @(posedge clk) begin
    if (resetn == 0) begin
        counter    <= 0;
        O          <= 0;
        previous_I <= 0;
    end

    if (I == previous_I) begin
        if (counter == 19) 
            O <= I;
        else
            counter <= counter + 1;
    end else begin
        counter    <= 0;
        previous_I <= I;
    end
end


endmodule
