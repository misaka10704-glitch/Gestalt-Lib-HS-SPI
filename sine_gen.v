`timescale 1ns / 1ps

/*
正弦伪 ADC：相位累加 + 64 点固定 LUT（8bit，可综合）
采样率 SAMPLE_HZ；默认每样步进 1 → f_sine ≈ SAMPLE_HZ/64
（SAMPLE_HZ=2000 → 约 31.25 Hz）
*/
module sine_gen#(
    parameter CLK_FREQ = 50_000_000,
    parameter SAMPLE_HZ = 2000,
    parameter PHASE_INC = 1
)
(
    input wire clk,
    input wire rst_n,
    input wire enable,
    output reg [7:0] sample,
    output reg sample_stb
);

localparam integer DIV = CLK_FREQ / SAMPLE_HZ;
localparam CNT_W = $clog2(DIV);

// round(127.5 + 127.5*sin(2*pi*k/64)), k=0..63
function automatic [7:0] sine_lut;
    input [5:0] idx;
    begin
        case(idx)
            6'd0:  sine_lut = 8'd128;
            6'd1:  sine_lut = 8'd140;
            6'd2:  sine_lut = 8'd152;
            6'd3:  sine_lut = 8'd164;
            6'd4:  sine_lut = 8'd176;
            6'd5:  sine_lut = 8'd187;
            6'd6:  sine_lut = 8'd198;
            6'd7:  sine_lut = 8'd208;
            6'd8:  sine_lut = 8'd217;
            6'd9:  sine_lut = 8'd226;
            6'd10: sine_lut = 8'd233;
            6'd11: sine_lut = 8'd239;
            6'd12: sine_lut = 8'd245;
            6'd13: sine_lut = 8'd249;
            6'd14: sine_lut = 8'd252;
            6'd15: sine_lut = 8'd254;
            6'd16: sine_lut = 8'd255;
            6'd17: sine_lut = 8'd254;
            6'd18: sine_lut = 8'd252;
            6'd19: sine_lut = 8'd249;
            6'd20: sine_lut = 8'd245;
            6'd21: sine_lut = 8'd239;
            6'd22: sine_lut = 8'd233;
            6'd23: sine_lut = 8'd226;
            6'd24: sine_lut = 8'd217;
            6'd25: sine_lut = 8'd208;
            6'd26: sine_lut = 8'd198;
            6'd27: sine_lut = 8'd187;
            6'd28: sine_lut = 8'd176;
            6'd29: sine_lut = 8'd164;
            6'd30: sine_lut = 8'd152;
            6'd31: sine_lut = 8'd140;
            6'd32: sine_lut = 8'd128;
            6'd33: sine_lut = 8'd115;
            6'd34: sine_lut = 8'd103;
            6'd35: sine_lut = 8'd91;
            6'd36: sine_lut = 8'd79;
            6'd37: sine_lut = 8'd68;
            6'd38: sine_lut = 8'd57;
            6'd39: sine_lut = 8'd47;
            6'd40: sine_lut = 8'd38;
            6'd41: sine_lut = 8'd29;
            6'd42: sine_lut = 8'd22;
            6'd43: sine_lut = 8'd16;
            6'd44: sine_lut = 8'd10;
            6'd45: sine_lut = 8'd6;
            6'd46: sine_lut = 8'd3;
            6'd47: sine_lut = 8'd1;
            6'd48: sine_lut = 8'd0;
            6'd49: sine_lut = 8'd1;
            6'd50: sine_lut = 8'd3;
            6'd51: sine_lut = 8'd6;
            6'd52: sine_lut = 8'd10;
            6'd53: sine_lut = 8'd16;
            6'd54: sine_lut = 8'd22;
            6'd55: sine_lut = 8'd29;
            6'd56: sine_lut = 8'd38;
            6'd57: sine_lut = 8'd47;
            6'd58: sine_lut = 8'd57;
            6'd59: sine_lut = 8'd68;
            6'd60: sine_lut = 8'd79;
            6'd61: sine_lut = 8'd91;
            6'd62: sine_lut = 8'd103;
            6'd63: sine_lut = 8'd115;
            default: sine_lut = 8'd128;
        endcase
    end
endfunction

reg [CNT_W-1:0] div_cnt;
reg [5:0] phase;

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        div_cnt<=0;
        phase<=0;
        sample<=8'd128;
        sample_stb<=0;
    end
    else begin
        sample_stb<=0;
        if(!enable)begin
            div_cnt<=0;
        end
        else if(div_cnt == DIV-1)begin
            div_cnt<=0;
            sample_stb<=1;
            sample<=sine_lut(phase);
            phase<=phase + PHASE_INC[5:0];
        end
        else begin
            div_cnt<=div_cnt+1'b1;
        end
    end
end

endmodule
