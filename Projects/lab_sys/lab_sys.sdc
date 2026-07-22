# 逻辑派 G1：sys_clk 默认 50MHz（周期 20ns）
create_clock -name sys_clk -period 20.000 -waveform {0 10.000} [get_ports {sys_clk}]

# 伪 ADC 时钟：sys_clk/50 → 1MHz（层次名见 TA1132：u_core/adc_clk）
create_generated_clock -name adc_clk -source [get_ports {sys_clk}] -divide_by 50 [get_nets {u_core/adc_clk}]

# 异步 FIFO 跨时钟：两域之间不做时序检查（靠 Gray 同步）
set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {adc_clk}]
