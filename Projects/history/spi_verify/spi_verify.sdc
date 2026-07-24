# 逻辑派 G1：sys_clk 默认 50MHz（周期 20ns）
create_clock -name sys_clk -period 20.000 -waveform {0 10.000} [get_ports {sys_clk}]
