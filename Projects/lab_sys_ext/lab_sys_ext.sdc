# sys_clk = 50MHz
create_clock -name sys_clk -period 20.000 -waveform {0 10.000} [get_ports {sys_clk}]
