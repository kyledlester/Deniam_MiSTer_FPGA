// Deniam MiSTer core -- sound: YM3812 + OKI M6295, with the deniam-16b Z80 board.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// docs/HARDWARE.md 7-9.
//   deniam-16b: Z80 (T80s) at 6.25 MHz: 0000-F7FF ROM, F800-FFFF RAM; I/O 01 R sound latch,
//     02/03 W YM3812, 05 R/W OKI, 07 W OKI bank (bit 6). NMI = latch "data pending" (set by the
//     68000 write, cleared by the Z80 read); INT = YM3812 IRQ (IM 1, 0xFF on the bus).
//   deniam-16c: no Z80; the 68000's chip writes arrive as host strobes (dnm_main.sv) and the OKI
//     status is copied back for C40001 reads. OKI bank = bit 0.
//   YM3812 (jtopl2) 4.1667 MHz; OKI M6295 (jt6295) 1.0417 MHz, pin 7 high.
//   Mono mix as MAME: YM x 0.60 + OKI x 1.00 (MAME scales OKI voices x16 against the YM's 16-bit
//   range), saturated; the same sample on both channels.
//
// Clocking: clk_snd = clk_sys / 2 = 50 MHz (same PLL, phase aligned). ce_z80 = clk_snd / 8,
// ce_opl = / 12, ce_oki = / 48. The download port, the 68000 interface and the OKI SDRAM client
// stay in the clk_sys domain (dual-clock ROM, toggle/level handshakes).
module dnm_sound #(
    parameter int Z_DIV = 8,            // clk_snd / Z_DIV = Z80; / OPL_DIV = YM3812; / OKI_DIV = OKI
    parameter int OPL_DIV = 12,         // (the sound bench runs a slower clk_snd with smaller dividers)
    parameter int OKI_DIV = 48
) (
    input  logic        clk,            // clk_sys
    input  logic        clk_snd,
    input  logic        reset,          // clk_sys domain
    input  logic        pause,          // clk_sys domain
    input  logic        b16c,

    input  logic  [7:0] latch,
    input  logic        latch_wr,       // clk_sys: one clock per 68000 write
    input  logic        host_wr,        // 16c: one clock per chip write
    input  logic  [1:0] host_sel,
    input  logic  [7:0] host_data,
    output logic  [7:0] oki_status,     // clk_sys copy of the OKI status

    // Z80 program download
    input  logic        rom_we,
    input  logic [15:0] rom_waddr,
    input  logic  [7:0] rom_wdata,

    // OKI sample ROM (SDRAM word reads through dnm_sdram_arb, 4-word bursts)
    output logic        oki_req,
    output logic [25:1] oki_addr,
    input  logic        oki_ack,
    input  logic [63:0] oki_data,

    output logic signed [15:0] snd,

    output logic [15:0] dbg_latch_reads,
    output logic [15:0] dbg_ym_writes,
    output logic [15:0] dbg_oki_writes,
    output logic [15:0] dbg_z80_irqs
);
    // ------------------------------------------------------------------ clk_snd domain basics
    logic [2:0]  rst_s = 3'b111;
    logic [1:0]  pause_s = 2'b00;
    logic [11:0] rst_cnt = '1;
    logic        rst = 1'b1;
    always_ff @(posedge clk_snd) begin
        rst_s   <= {rst_s[1:0], reset};
        pause_s <= {pause_s[0], pause};
        if (rst_s[1] && !rst_s[2]) rst_cnt <= '1;
        else if (rst_cnt != 0) rst_cnt <= rst_cnt - 12'd1;
        rst <= rst_s[1] || rst_cnt != 0;
    end

    logic [5:0] cz = '0;
    logic [5:0] co = '0;
    logic [5:0] ck = '0;
    logic       ce_z80, ce_opl, ce_oki;
    always_ff @(posedge clk_snd) begin
        ce_z80 <= 1'b0;
        ce_opl <= 1'b0;
        ce_oki <= 1'b0;
        if (!pause_s[1] || rst) begin
            cz <= (cz == 6'(Z_DIV - 1))   ? 6'd0 : cz + 6'd1;
            co <= (co == 6'(OPL_DIV - 1)) ? 6'd0 : co + 6'd1;
            ck <= (ck == 6'(OKI_DIV - 1)) ? 6'd0 : ck + 6'd1;
            ce_z80 <= cz == 6'(Z_DIV - 1);
            ce_opl <= co == 6'(OPL_DIV - 1);
            ce_oki <= ck == 6'(OKI_DIV - 1);
        end
    end

    // ------------------------------------------------------------------ 68000 -> sound crossings
    logic       lat_tgl = 1'b0;
    always_ff @(posedge clk) if (latch_wr) lat_tgl <= !lat_tgl;
    logic [7:0] latch_s;
    logic [2:0] lat_tgl_s = '0;
    logic       pending;
    logic       lat_rd;
    always_ff @(posedge clk_snd) begin
        lat_tgl_s <= {lat_tgl_s[1:0], lat_tgl};
        latch_s   <= latch;
        if (rst) pending <= 1'b0;
        else if (lat_tgl_s[2] != lat_tgl_s[1]) pending <= 1'b1;
        else if (lat_rd) pending <= 1'b0;
    end

    // 16c host writes: value registered in clk_sys, toggle crossing; the 68000 cannot issue two
    // chip writes closer than a few hundred ns, far longer than the crossing.
    logic       h_tgl = 1'b0;
    logic [1:0] h_sel;
    logic [7:0] h_data;
    always_ff @(posedge clk) if (host_wr) begin h_tgl <= !h_tgl; h_sel <= host_sel; h_data <= host_data; end
    logic [2:0] h_tgl_s = '0;
    logic       h_wr;
    always_ff @(posedge clk_snd) begin
        h_tgl_s <= {h_tgl_s[1:0], h_tgl};
        h_wr    <= h_tgl_s[2] != h_tgl_s[1];
    end

    // ------------------------------------------------------------------ Z80 (deniam-16b)
    logic        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n;
    logic [15:0] A;
    logic  [7:0] cpu_di, cpu_do;
    logic        opl_irq_n;

    T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80 (
        .RESET_n(!(rst || b16c)), .CLK(clk_snd), .CEN(ce_z80), .WAIT_n(1'b1), .INT_n(opl_irq_n), .NMI_n(!pending),
        .BUSRQ_n(1'b1), .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
        .RFSH_n(rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(A), .DI(cpu_di), .DO(cpu_do));

    wire mem     = !mreq_n && rfsh_n;
    wire io      = !iorq_n && m1_n;
    wire sel_rom = mem && A < 16'hF800;
    wire sel_ram = mem && A >= 16'hF800;
    wire sel_lat = io && A[7:0] == 8'h01;
    wire sel_ym  = io && A[7:1] == 7'b0000_001;         // 02-03
    wire sel_oki = io && A[7:0] == 8'h05;
    wire sel_bnk = io && A[7:0] == 8'h07;

    logic [7:0] rom_q, ram_q;
    dnm_dcram #(.AW(16), .DW(8)
`ifdef DNM_SIM_Z80ROM
        , .INIT(`DNM_SIM_Z80ROM)
`endif
    ) rom (.wclk(clk), .w_addr(rom_waddr), .we(rom_we), .din(rom_wdata),
           .rclk(clk_snd), .r_addr(A), .dout(rom_q));

    logic wr_n_d, rd_n_q;
    always_ff @(posedge clk_snd) begin wr_n_d <= wr_n; rd_n_q <= rd_n; end
    wire wr_edge = wr_n_d && !wr_n;
    assign lat_rd = sel_lat && rd_n_q && !rd_n;

    dnm_dpram #(.AW(11), .DW(8)) ram (
        .clk(clk_snd), .a_addr(A[10:0]), .a_we(sel_ram && wr_edge), .a_din(cpu_do), .a_dout(ram_q),
        .b_addr(11'd0), .b_dout());

    // ------------------------------------------------------------------ chip write ports
    wire        z_ym_wr  = !b16c && sel_ym && wr_edge;
    wire        z_oki_wr = !b16c && sel_oki && wr_edge;
    wire        z_bnk_wr = !b16c && sel_bnk && wr_edge;
    wire        ym_wr    = z_ym_wr  || (b16c && h_wr && h_sel[1]);
    wire        ym_a0    = b16c ? h_sel[0] : A[0];
    wire        oki_wr   = z_oki_wr || (b16c && h_wr && h_sel == 2'd0);
    wire  [7:0] wdata    = b16c ? h_data : cpu_do;

    logic oki_bank;
    always_ff @(posedge clk_snd) begin
        if (rst) oki_bank <= 1'b0;                      // MAME machine_reset: bank 0
        else if (z_bnk_wr) oki_bank <= cpu_do[6];
        else if (b16c && h_wr && h_sel == 2'd1) oki_bank <= h_data[0];
    end

    // ------------------------------------------------------------------ YM3812
    logic signed [15:0] ym_snd;
    jtopl2 ym (
        .rst(rst), .clk(clk_snd), .cen(ce_opl), .din(wdata), .addr(ym_a0),
        .cs_n(!ym_wr), .wr_n(!ym_wr), .dout(), .irq_n(opl_irq_n), .snd(ym_snd), .sample());

    // ------------------------------------------------------------------ OKI M6295
    logic [7:0]  oki_dout;
    logic [17:0] oki_rom_addr;
    logic [7:0]  oki_rom_data;
    logic        oki_rom_ok;
    logic signed [13:0] oki_snd;
    jt6295 #(.INTERPOL(0)) oki (
        .rst(rst), .clk(clk_snd), .cen(ce_oki), .ss(1'b1),
        .wrn(!oki_wr), .din(wdata), .dout(oki_dout),
        .rom_addr(oki_rom_addr), .rom_data(oki_rom_data), .rom_ok(oki_rom_ok),
        .sound(oki_snd), .sample());

    logic [7:0] oki_status_s;
    always_ff @(posedge clk_snd) oki_status_s <= oki_dout;
    always_ff @(posedge clk) oki_status <= oki_status_s;

    // 8-byte line cache in front of SDRAM (OKI region at SDRAM word 0x380000, bytes little-endian
    // within each word). Sample byte address = {bank, rom_addr[17:0]}. Crossing to the clk_sys
    // SDRAM port by a level handshake (as the owner's Final Star Force core).
    wire  [18:0] oki_a = {oki_bank, oki_rom_addr};
    logic [15:0] line_tag, fill_tag;
    logic        line_valid;
    logic [63:0] line_data, fill_data;
    logic        fill_rq, fill_done;
    wire hit = line_valid && line_tag == oki_a[18:3];
    always_ff @(posedge clk_snd) begin
        if (rst) begin
            line_valid <= 1'b0;
            fill_rq    <= 1'b0;
        end else if (fill_rq) begin
            if (fill_done) begin
                fill_rq    <= 1'b0;
                line_data  <= fill_data;
                line_tag   <= fill_tag;
                line_valid <= 1'b1;
            end
        end else if (!hit && !fill_done) begin
            fill_rq  <= 1'b1;
            fill_tag <= oki_a[18:3];
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            oki_req   <= 1'b0;
            fill_done <= 1'b0;
        end else if (!fill_rq) begin
            fill_done <= 1'b0;
        end else if (!fill_done) begin
            if (!oki_req) begin
                oki_req  <= 1'b1;
                oki_addr <= 25'h380000 + {7'd0, fill_tag, 2'b00};
            end else if (oki_ack) begin
                oki_req   <= 1'b0;
                fill_data <= oki_data;
                fill_done <= 1'b1;
            end
        end
    end
    assign oki_rom_ok   = hit;
    assign oki_rom_data = line_data[oki_a[2:0]*8 +: 8];

    // ------------------------------------------------------------------ Z80 read mux
    always_comb begin
        cpu_di = 8'h00;                                 // MAME unmapped read value
        if (sel_rom)      cpu_di = rom_q;
        else if (sel_ram) cpu_di = ram_q;
        else if (sel_lat) cpu_di = latch_s;
        else if (sel_oki) cpu_di = oki_dout;
        else if (!iorq_n && !m1_n) cpu_di = 8'hFF;      // IM 1 acknowledge (bus floats high)
    end

    // ------------------------------------------------------------------ mix
    function automatic logic signed [15:0] sat(input logic signed [25:0] v);
        sat = (v > 26'sd32767) ? 16'sd32767 : (v < -26'sd32768) ? 16'sh8000 : v[15:0];
    endfunction
    logic signed [15:0] snd_s;
    always_ff @(posedge clk_snd)
        snd_s <= sat(($signed(ym_snd) * 26'sd77 + $signed(oki_snd) * 26'sd2048) >>> 7);  // 0.60, 16 x 1.00
    always_ff @(posedge clk) snd <= snd_s;

    // ------------------------------------------------------------------ debug counters
    logic irq_n_d;
    always_ff @(posedge clk_snd) begin
        irq_n_d <= opl_irq_n;
        if (rst) begin
            dbg_latch_reads <= '0; dbg_ym_writes <= '0; dbg_oki_writes <= '0; dbg_z80_irqs <= '0;
        end else begin
            if (lat_rd) dbg_latch_reads <= dbg_latch_reads + 16'd1;
            if (ym_wr) dbg_ym_writes <= dbg_ym_writes + 16'd1;
            if (oki_wr) dbg_oki_writes <= dbg_oki_writes + 16'd1;
            if (irq_n_d && !opl_irq_n) dbg_z80_irqs <= dbg_z80_irqs + 16'd1;
        end
    end
endmodule
