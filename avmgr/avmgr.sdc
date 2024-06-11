
create_clock -name clk25 -period 40 [get_ports {CLK25}]
create_clock -name ale -period 50 [get_ports {B_ALEn}]

# ALE to CLK25 transfer
set_false_path -from {b_a_hi[*]} -to [get_clocks {clk25}]
set_false_path -from {l_reg_sel[*]} -to [get_clocks {clk25}]
