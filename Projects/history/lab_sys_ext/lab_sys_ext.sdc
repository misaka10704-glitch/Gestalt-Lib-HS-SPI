# lab_sys_ext clocks
# 板载晶振 → sys_clk 50MHz
create_clock -name sys_clk -period 20.000 -waveform {0 10.000} [get_ports {sys_clk}]

# rPLL：50 → 200MHz（消除 pll 相关 STA 缺口；网名若报错可注释）
create_generated_clock -name pll_clk_200 -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 4 [get_nets {pll_clk_200}]

# ---- 关于 TA1132 (adc_clk / eng_clk not created) ----
# 那是「内部钟没写进 SDC」的分析警告，不是时钟没造出来。
# adc_clk = sys 分频；eng_clk = sys/pll mux。功能上照样跳，与 UART 空白无关。
# 若要坚持声明，在 Place&Route 后用报告里的真实网名再补 create_generated_clock。
