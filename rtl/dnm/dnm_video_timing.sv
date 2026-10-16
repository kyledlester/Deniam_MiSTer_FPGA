// Deniam MiSTer core -- raster timing.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// 6.25 MHz pixel clock, 400 dots x 262 lines = 15.625 kHz / 59.64 Hz (docs/HARDWARE.md 3; MAME uses
// 60 Hz with no raster model). hcount = output dot (board x = 188 + hcount for 0..319), vcount =
// board line (visible 0..223). Sync placement is a MiSTer/CRT choice (not PCB-verified):
//   H: active 0..319, front porch 320..335, HSync 336..365 (4.8 us), back porch 366..399.
//   V: active 0..223, front porch 224..231, VSync 232..234, back porch 235..261.
// line_start: one clk_sys pulse on the ce_pix that enters dot 0 of a line, with vcount valid.
// Reset phase: MAME starts its screen at vblank begin, so the raster leaves reset at line 224.
module dnm_video_timing (
    input  logic       clk,
    input  logic       rst,
    input  logic       ce_pix,
    output logic [8:0] hcount,     // 0..399
    output logic [8:0] vcount,     // 0..261
    output logic       hblank,
    output logic       vblank,
    output logic       hsync,
    output logic       vsync,
    output logic       line_start
);
`ifdef DNM_MAME_TIMING
    // Simulation only (whole-board comparisons with MAME traces): MAME's frame is exactly 1/60 s =
    // 104166.67 dots. Lines are 397 dots; lines 260 and 261 are stretched to 473 dots, line 261 to
    // 474 in two frames out of three (262 x 397 + 152.67).
    logic [1:0] fcnt;
    wire  [8:0] last_dot = (vcount < 9'd260) ? 9'd396 : (vcount == 9'd261 && fcnt != 2'd2) ? 9'd473 : 9'd472;
    always_ff @(posedge clk)
        if (rst) fcnt <= '0;
        else if (ce_pix && hcount == last_dot && vcount == 9'd261) fcnt <= (fcnt == 2'd2) ? 2'd0 : fcnt + 2'd1;
`else
    wire  [8:0] last_dot = 9'd399;
`endif

    always_ff @(posedge clk) begin
        line_start <= 1'b0;
        if (rst) begin
            hcount <= '0;
            vcount <= 9'd224;
        end else if (ce_pix) begin
            if (hcount == last_dot) begin
                hcount     <= '0;
                vcount     <= (vcount == 9'd261) ? 9'd0 : vcount + 9'd1;
                line_start <= 1'b1;
            end else
                hcount <= hcount + 9'd1;
        end
    end

    always_comb begin
        hblank = hcount >= 9'd320;
        vblank = vcount >= 9'd224;
        hsync  = (hcount >= 9'd336) && (hcount <= 9'd365);
        vsync  = (vcount >= 9'd232) && (vcount <= 9'd234);
    end
endmodule
