// Deniam MiSTer core -- board top (deniam-16b: Logic Pro, Croquis, Karian Cross; deniam-16c: Logic Pro 2).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// docs/ARCHITECTURE.md, docs/HARDWARE.md. Everything runs on clk_sys (100 MHz) with clock enables:
//   dnm_clocks        -> ce_pix 6.25 MHz, FX68K phi1/phi2 (12.5 MHz)
//   dnm_video_timing  -> 400 x 262 raster; vblank event at line 224 (IRQ 4)
//   dnm_loader        -> ROM stream to SDRAM / Z80 block RAM
//   dnm_main          -> 68000 board (program ROM cache in front of SDRAM)
//   dnm_video         -> tilemaps, sprites, mixer        dnm_sound -> Z80, YM3812, OKI (clk_snd)
//   dnm_sdram_arb     -> SDRAM channel 1 (loader > 68000 > OKI > tilemaps > sprites)
module dnm_core (
    input  logic        clk,
    input  logic        clk_snd,
    input  logic        init,
    input  logic        reset,
    input  logic        pause,

    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [15:0] ioctl_dout,
    output logic        ioctl_wait,

    output logic [26:1] sd_addr,
    output logic [15:0] sd_din,
    output logic  [1:0] sd_be,
    output logic        sd_req,
    output logic        sd_rnw,
    input  logic [63:0] sd_dout,
    input  logic        sd_ready,

    input  logic [31:0] joy0,
    input  logic [31:0] joy1,
    input  logic        service,        // OSD: hold the service-mode input
    input  logic        osd_flip,
    input  logic        test_pattern,
    input  logic        dbg_overlay,

    output logic  [7:0] game_cfg,       // MRA index 1: bit 0 deniam-16c, bit 1 karianx offsets
    output logic        ce_pix,
    output logic [23:0] rgb,
    output logic        hblank,
    output logic        vblank,
    output logic        hsync,
    output logic        vsync,
    output logic        vb_next,
    output logic signed [15:0] snd
);
    // ------------------------------------------------------------------ clocks / raster
    logic phi1, phi2, cpu_wait;
    dnm_clocks clocks (
        .clk(clk), .rst(reset), .rst_video(init), .pause(pause), .cpu_wait(cpu_wait),
        .ce_pix(ce_pix), .phi1(phi1), .phi2(phi2));

    logic [8:0] hcount, vcount;
    logic hb, vb, hs, vs, line_start;
    dnm_video_timing timing (
        .clk(clk), .rst(init), .ce_pix(ce_pix),
        .hcount(hcount), .vcount(vcount), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
        .line_start(line_start));

    wire vblank_evt = line_start && vcount == 9'd224 && !pause;

    // ------------------------------------------------------------------ game select (index 1)
    logic [7:0] cfg_r = 8'h00;
    always_ff @(posedge clk)
        if (ioctl_download && ioctl_wr && ioctl_index == 16'd1 && ioctl_addr[26:1] == 0)
            cfg_r <= ioctl_dout[7:0];
    assign game_cfg = cfg_r;
    wire b16c    = cfg_r[0];
    wire karianx = cfg_r[1];

    // ------------------------------------------------------------------ DIP switches (index 254)
    logic [7:0] dsw = 8'hFF;
    always_ff @(posedge clk)
        if (ioctl_download && ioctl_wr && ioctl_index == 16'd254 && ioctl_addr[26:1] == 0)
            dsw <= ioctl_dout[7:0];

    // ------------------------------------------------------------------ inputs (docs/HARDWARE.md 5)
    // MiSTer joystick: 0 right, 1 left, 2 down, 3 up, 4-6 buttons 1-3, 7 start, 8 coin, 9 pause.
    wire [7:0] in_p1 = ~{joy0[1], joy0[0], joy0[3], joy0[2], 1'b0, joy0[6], joy0[5], joy0[4]};
    wire [7:0] in_p2 = ~{joy1[1], joy1[0], joy1[3], joy1[2], 1'b0, joy1[6], joy1[5], joy1[4]};
    wire [7:0] in_system = ~{2'b00, joy1[7], joy0[7], 1'b0, service, joy1[8], joy0[8]};

    // ------------------------------------------------------------------ loader
    logic        ld_req, ld_ack;
    logic [25:1] ld_addr;
    logic [15:0] ld_wdata;
    logic        romz80_we;
    logic [15:0] romz80_addr;
    logic  [7:0] romz80_data;
    logic        loaded;
    dnm_loader loader (
        .clk(clk), .rst(init),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
        .mem_req(ld_req), .mem_addr(ld_addr), .mem_wdata(ld_wdata), .mem_ack(ld_ack),
        .romz80_we(romz80_we), .romz80_addr(romz80_addr), .romz80_data(romz80_data),
        .loaded(loaded));

    // ------------------------------------------------------------------ 68000 board
    logic        rom_req, rom_ack;
    logic [25:1] rom_addr;
    logic  [7:0] latch;
    logic        latch_wr, host_wr;
    logic  [1:0] host_sel;
    logic  [7:0] host_data, oki_status;
    logic [15:0] coinctrl;
    logic [15:0] vregs [6];
    logic [14:0] vram_addr;
    logic [15:0] vram_q, txt_q, pal_q;
    logic [10:0] txt_addr, pal_addr;
    logic  [6:0] spr_addr;
    logic [79:0] spr_q;
    logic [63:0] mem_rdata;
    logic [23:0] dbg_pc;
    logic [15:0] dbg_irq, dbg_frames, dbg_latch, dbg_misses;
    dnm_main main (
        .clk(clk), .reset(reset), .rom_flush(ioctl_download), .b16c(b16c),
        .phi1(phi1), .phi2(phi2), .cpu_wait(cpu_wait), .vblank_evt(vblank_evt),
        .in_system(in_system), .in_p1(in_p1), .in_p2(in_p2), .in_dsw(dsw),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ack(rom_ack), .rom_data(mem_rdata),
        .snd_latch(latch), .snd_latch_wr(latch_wr),
        .host_wr(host_wr), .host_sel(host_sel), .host_data(host_data), .oki_status(oki_status),
        .coinctrl(coinctrl), .vregs(vregs),
        .vram_addr(vram_addr), .vram_q(vram_q), .txt_addr(txt_addr), .txt_q(txt_q),
        .pal_addr(pal_addr), .pal_q(pal_q), .spr_addr(spr_addr), .spr_q(spr_q),
        .dbg_pc(dbg_pc), .dbg_irq(dbg_irq), .dbg_frames(dbg_frames),
        .dbg_latch_writes(dbg_latch), .dbg_misses(dbg_misses));

    // ------------------------------------------------------------------ video
    logic        tm_req, tm_ack, sp_req, sp_ack;
    logic [25:1] tm_addr, sp_addr;
    logic [23:0] vid_rgb;
    logic        vhb, vvb, vhs, vvs;
    logic [15:0] dbg_overruns;
    dnm_video video (
        .clk(clk), .rst(reset), .ce_pix(ce_pix), .hcount(hcount), .vcount(vcount), .line_start(line_start),
        .hblank_in(hb), .vblank_in(vb), .hsync_in(hs), .vsync_in(vs),
        .karianx(karianx), .vregs(vregs), .coinctrl(coinctrl), .osd_flip(osd_flip),
        .vram_addr(vram_addr), .vram_q(vram_q), .txt_addr(txt_addr), .txt_q(txt_q),
        .pal_addr(pal_addr), .pal_q(pal_q), .spr_addr(spr_addr), .spr_q(spr_q),
        .tm_req(tm_req), .tm_addr(tm_addr), .tm_ack(tm_ack),
        .sp_req(sp_req), .sp_addr(sp_addr), .sp_ack(sp_ack), .mem_data(mem_rdata),
        .rgb(vid_rgb), .hblank(vhb), .vblank(vvb), .hsync(vhs), .vsync(vvs), .dbg_overruns(dbg_overruns));

    // ------------------------------------------------------------------ sound
    logic        oki_req, oki_ack;
    logic [25:1] oki_addr;
    logic [15:0] dbg_lat_rd, dbg_ym, dbg_oki, dbg_zirq;
`ifdef DNM_SIM_NO_SOUND
    assign snd = '0; assign oki_req = 1'b0; assign oki_addr = '0; assign oki_status = 8'h00;
    assign {dbg_lat_rd, dbg_ym, dbg_oki, dbg_zirq} = '0;
`else
    dnm_sound sound (
        .clk(clk), .clk_snd(clk_snd), .reset(reset), .pause(pause), .b16c(b16c),
        .latch(latch), .latch_wr(latch_wr),
        .host_wr(host_wr), .host_sel(host_sel), .host_data(host_data), .oki_status(oki_status),
        .rom_we(romz80_we), .rom_waddr(romz80_addr), .rom_wdata(romz80_data),
        .oki_req(oki_req), .oki_addr(oki_addr), .oki_ack(oki_ack), .oki_data(mem_rdata),
        .snd(snd),
        .dbg_latch_reads(dbg_lat_rd), .dbg_ym_writes(dbg_ym), .dbg_oki_writes(dbg_oki), .dbg_z80_irqs(dbg_zirq));
`endif

    // ------------------------------------------------------------------ SDRAM
    logic [4:0]  arb_ack;
    logic [25:1] arb_addr [5];
    assign arb_addr[0] = ld_addr;
    assign arb_addr[1] = rom_addr;
    assign arb_addr[2] = oki_addr;
    assign arb_addr[3] = tm_addr;
    assign arb_addr[4] = sp_addr;
    dnm_sdram_arb #(.N(5)) arb (
        .clk(clk), .rst(init),
        .req({sp_req, tm_req, oki_req, rom_req, ld_req}), .addr(arb_addr), .we(5'b00001),
        .wdata(ld_wdata), .wbe(2'b11), .ack(arb_ack), .rdata(mem_rdata),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_req(sd_req), .sd_rnw(sd_rnw),
        .sd_dout(sd_dout), .sd_ready(sd_ready));
    assign ld_ack  = arb_ack[0];
    assign rom_ack = arb_ack[1];
    assign oki_ack = arb_ack[2];
    assign tm_ack  = arb_ack[3];
    assign sp_ack  = arb_ack[4];

    // ------------------------------------------------------------------ output (test pattern / debug overlay)
    logic [23:0] ovl_rgb;
    dnm_overlay overlay (
        .clk(clk), .ce_pix(ce_pix), .hcount(hcount), .vcount(vcount), .enable(dbg_overlay),
        .values({ {8'h00, dbg_pc}, {dbg_frames, dbg_irq}, {dbg_latch, dbg_lat_rd},
                  {dbg_zirq, dbg_misses}, {dbg_ym, dbg_oki}, {dbg_overruns, cfg_r, 7'd0, loaded} }),
        .rgb_in(vid_rgb), .rgb_out(ovl_rgb));

    always_ff @(posedge clk) if (ce_pix) begin
        if (test_pattern) begin
            // 8 colour bars across the active width with a white border, raster timing unchanged
            if (hcount == 9'd1 || hcount == 9'd320 || vcount == 9'd0 || vcount == 9'd223)
                rgb <= 24'hFFFFFF;
            else begin
                logic [2:0] bar;
                bar = 3'((hcount - 9'd1) / 9'd40);
                rgb <= {{8{bar[2]}}, {8{bar[1]}}, {8{bar[0]}}};
            end
        end else
            rgb <= ovl_rgb;
        {hblank, vblank, hsync, vsync} <= {vhb, vvb, vhs, vvs};
        // the output stream lags the raster counters by a few dots, so vcount is still the output
        // line when its active area ends (where dnm_crt_adjust samples this)
        vb_next <= !(vcount + 9'd1 < 9'd224 || vcount == 9'd261);
    end
endmodule
