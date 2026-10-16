// Deniam MiSTer core -- system PLL.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One PLL: 50 MHz board clock -> clk_sys = 100 MHz (4 x the board's 25 MHz crystal: 6.25 MHz pixel
// clock and 12.5 MHz 68000 as integer enables, dnm_clocks.sv; also the SDRAM clock) and
// clk_snd = 50 MHz (sound domain: Z80 6.25 MHz = /8, YM3812 4.1667 MHz = /12, OKI 1.0417 MHz = /48).
//
// HIERARCHY IS LOAD-BEARING: sys/sys_top.sdc places the core clock in its own clock group only if
// it matches *|pll|pll_inst|altera_pll_i|*[*].*|divclk, so emu instantiates this module as "pll"
// (same shape as a MegaWizard MiSTer PLL; pattern from the owner's NB-1 / Final Star Force cores).
module dnm_pll (
    input  wire refclk,   // CLK_50M
    input  wire rst,
    output wire clk_sys,  // 100 MHz
    output wire clk_snd,  // 50 MHz = clk_sys / 2, phase aligned
    output wire locked
);
    dnm_pll_core pll_inst (
        .refclk(refclk),
        .rst(rst),
        .clk_sys(clk_sys),
        .clk_snd(clk_snd),
        .locked(locked)
    );
endmodule

module dnm_pll_core (
    input  wire refclk,
    input  wire rst,
    output wire clk_sys,
    output wire clk_snd,
    output wire locked
);
    wire [1:0] clocks;

    altera_pll #(
        .fractional_vco_multiplier("false"),
        .reference_clock_frequency("50.0 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(2),
        .output_clock_frequency0("100.000000 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("50.000000 MHz"),
        .phase_shift1("0 ps"),
        .duty_cycle1(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .refclk(refclk),
        .rst(rst),
        .outclk(clocks),
        .locked(locked),
        .fboutclk(),
        .fbclk(1'b0)
    );

    assign clk_sys = clocks[0];
    assign clk_snd = clocks[1];
endmodule
