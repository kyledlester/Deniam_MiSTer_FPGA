// Deniam MiSTer core -- clock enables.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// clk_sys = 100 MHz (dnm_pll.sv) = 4 x the board's 25 MHz crystal, so every board clock is an
// exact integer enable:
//   ce_pix   : clk_sys / 16 = 6.25 MHz (25/4 pixel clock, 400 x 262 raster)
//   phi1/phi2: FX68K phase enables -> 68000 at 12.5 MHz (25/2): one phase every 4 clk_sys.
// The sound section (Z80, YM3812, OKI) derives its enables from clk_snd (dnm_sound.sv).
//
// Wait-state catch-up: MAME's 68000 never waits, but a program-cache miss (dnm_rom_cache) costs the
// FX68K wait clocks. dnm_main reports every wait clock (cpu_wait); this generator keeps the 68000's
// effective cycle count (clocks executed minus wait clocks) on the exact 12.5 MHz schedule by issuing
// phases every 3 clk_sys (16.7 MHz) while it is behind. With no debt the phases fall on exactly the
// same clocks as a plain /4 divider, so the CPU's time base matches MAME's cycle for cycle.
// pause freezes the 68000 and its schedule (the raster keeps running).
module dnm_clocks (
    input  logic clk,
    input  logic rst,          // emulated time base reset
    input  logic rst_video,    // raster divider reset (PLL loss only)
    input  logic pause,
    input  logic cpu_wait,     // one pulse per 68000 wait clock (2 phases owed)
    output logic ce_pix,
    output logic phi1,
    output logic phi2
);
    logic [3:0] pdiv;
    always_ff @(posedge clk) begin
        ce_pix <= 1'b0;
        if (rst_video) pdiv <= '0;
        else begin
            pdiv <= pdiv + 4'd1;
            if (pdiv == 4'd15) ce_pix <= 1'b1;
        end
    end

    logic [1:0]  tdiv;          // ideal phase every 4 clk_sys
    logic [9:0]  debt;          // phases the CPU is behind its schedule (incl. the one due now)
    logic [1:0]  since;         // clk_sys since the last phase, saturating at 3
    logic        next2;         // next phase is phi2
    wire         due   = tdiv == 2'd3;
    wire  [9:0]  owed  = debt + {9'd0, due};
    wire         issue = owed != 0 && since == 2'd3;     // phases at least 3 clk_sys apart

    always_ff @(posedge clk) begin
        phi1 <= 1'b0;
        phi2 <= 1'b0;
        if (rst) begin
            tdiv  <= '0;
            debt  <= '0;
            since <= 2'd3;
            next2 <= 1'b0;
        end else if (!pause) begin
            tdiv  <= tdiv + 2'd1;
            debt  <= owed - {9'd0, issue} + (cpu_wait ? 10'd2 : 10'd0);
            since <= issue ? 2'd1 : (since == 2'd3 ? 2'd3 : since + 2'd1);
            if (issue) begin
                phi1  <= !next2;
                phi2  <= next2;
                next2 <= !next2;
            end
        end
    end
endmodule
