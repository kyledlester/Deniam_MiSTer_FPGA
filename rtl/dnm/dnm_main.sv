// Deniam MiSTer core -- 68000 main board.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// MAME 0.289 deniam.cpp base_main_map / main_map (docs/HARDWARE.md 4): FX68K at 12.5 MHz, program ROM
// in SDRAM behind dnm_rom_cache, work RAM / tilemap RAM / text RAM / sprite RAM / palette RAM in
// block RAM (dual-ported to the video side), I/O, the coin/display control register, the IRQ 4
// level (asserted at vblank begin, released by a write to C40004) and the sound interface:
// deniam-16b: the 8-bit sound latch at C40000; deniam-16c: direct OKI / OKI bank / YM3812 writes
// (passed to dnm_sound as one-clock host write strobes) and the OKI status read at C40001.
module dnm_main (
    input  logic        clk,
    input  logic        reset,
    input  logic        rom_flush,      // ROM download in progress
    input  logic        b16c,           // board: 0 = deniam-16b (Z80 sound), 1 = deniam-16c
    input  logic        phi1,
    input  logic        phi2,
    output logic        cpu_wait,       // one pulse per 68000 wait clock (to dnm_clocks)

    input  logic        vblank_evt,     // start of line 224 (gated by pause)

    input  logic  [7:0] in_system,      // MAME port values (active low)
    input  logic  [7:0] in_p1,
    input  logic  [7:0] in_p2,
    input  logic  [7:0] in_dsw,

    // program ROM in SDRAM
    output logic        rom_req,
    output logic [25:1] rom_addr,
    input  logic        rom_ack,
    input  logic [63:0] rom_data,

    // sound
    output logic  [7:0] snd_latch,
    output logic        snd_latch_wr,   // 16b: one clock per write
    output logic        host_wr,        // 16c: one clock per chip write
    output logic  [1:0] host_sel,       // 0 OKI, 1 OKI bank, 2 YM address, 3 YM data
    output logic  [7:0] host_data,
    input  logic  [7:0] oki_status,     // 16c: OKI read (clk domain copy)

    output logic [15:0] coinctrl,
    output logic [15:0] vregs [6],      // text RAM words 0x51..0x56 (docs/HARDWARE.md 6.2)

    // video read ports (registered, 1 clock)
    input  logic [14:0] vram_addr,
    output logic [15:0] vram_q,
    input  logic [10:0] txt_addr,
    output logic [15:0] txt_q,
    input  logic [10:0] pal_addr,
    output logic [15:0] pal_q,
    input  logic  [6:0] spr_addr,       // sprite entry
    output logic [79:0] spr_q,          // words 4..0 of the entry

    output logic [23:0] dbg_pc,
    output logic [15:0] dbg_irq,
    output logic [15:0] dbg_frames,
    output logic [15:0] dbg_latch_writes,
    output logic [15:0] dbg_misses
);
    // ------------------------------------------------------------------ CPU
    logic [2:0]  irq_level;
    logic        iack_service, iack_active, vpa_n;
    logic [2:0]  iack_level;
    logic        cpu_req, cpu_write;
    logic [23:0] cpu_addr;
    logic [15:0] cpu_wdata, cpu_rdata;
    logic [1:0]  cpu_be;
    logic        cpu_ack;
    logic [71:0] dbg_native;

    dnm_cpu68k cpu (
        .clk_sys(clk), .reset(reset), .en_phi1(phi1), .en_phi2(phi2),
        .irq_level(irq_level), .iack_service(iack_service), .iack_level(iack_level),
        .iack_active(iack_active), .vpa_n(vpa_n),
        .cpu_req(cpu_req), .cpu_write(cpu_write), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_byte_en(cpu_be), .cpu_rdata(cpu_rdata), .cpu_ack(cpu_ack),
        .debug_native(dbg_native)
    );

    wire [2:0] fc = dbg_native[65:63];
    always_ff @(posedge clk)
        if (!dbg_native[57] && fc[1:0] == 2'b10) dbg_pc <= dbg_native[23:0];

    // Wait clocks: a zero-wait-state bus cycle has AS low for exactly 2 phi1 phases; each further
    // phi1 with AS low is a wait clock MAME's 68000 does not have (only program-cache misses).
    // Interrupt-acknowledge cycles (FC = 7, autovectored through VPA) are not counted.
    logic [1:0] as_phi;
    wire        as_cyc = !dbg_native[57] && fc != 3'b111;
    always_ff @(posedge clk)
        if (reset || !as_cyc) as_phi <= '0;
        else if (phi1 && as_phi != 2'd2) as_phi <= as_phi + 2'd1;
    assign cpu_wait = as_cyc && phi1 && as_phi == 2'd2;

    // ------------------------------------------------------------------ decode
    wire [23:0] a = cpu_addr;
    wire sel_rom  = a[23:20] == 4'h0;                  // 000000-0FFFFF
    wire sel_vram = a[23:16] == 8'h40;                 // 400000-40FFFF
    wire sel_txt  = a[23:12] == 12'h410;               // 410000-410FFF
    wire sel_spr  = a[23:11] == 13'h0880;              // 440000-4407FF
    wire sel_pal  = a[23:12] == 12'h840;               // 840000-840FFF
    wire sel_io0  = a[23:4]  == 20'hC4000;             // C40000-C4000F
    wire sel_io1  = a[23:4]  == 20'hC4400;             // C44000-C4400F
    wire sel_ram  = a[23:16] == 8'hFF;                 // FF0000-FFFFFF

    // ------------------------------------------------------------------ memories
    logic        acc_we;
    logic [15:0] ram_q, txt_cq, vram_cq;

    dnm_spram16 #(.AW(15)) ram (
        .clk(clk), .addr(a[15:1]), .we({2{acc_we && sel_ram}} & cpu_be), .din(cpu_wdata), .dout(ram_q));

    // CPU on port A (byte lanes), video on port B
    dnm_dpram #(.AW(11), .DW(8)) txt_hi (.clk(clk), .a_addr(a[11:1]), .a_we(acc_we && sel_txt && cpu_be[1]),
        .a_din(cpu_wdata[15:8]), .a_dout(txt_cq[15:8]), .b_addr(txt_addr), .b_dout(txt_q[15:8]));
    dnm_dpram #(.AW(11), .DW(8)) txt_lo (.clk(clk), .a_addr(a[11:1]), .a_we(acc_we && sel_txt && cpu_be[0]),
        .a_din(cpu_wdata[7:0]), .a_dout(txt_cq[7:0]), .b_addr(txt_addr), .b_dout(txt_q[7:0]));
    dnm_dpram #(.AW(15), .DW(8)) vram_hi (.clk(clk), .a_addr(a[15:1]), .a_we(acc_we && sel_vram && cpu_be[1]),
        .a_din(cpu_wdata[15:8]), .a_dout(vram_cq[15:8]), .b_addr(vram_addr), .b_dout(vram_q[15:8]));
    dnm_dpram #(.AW(15), .DW(8)) vram_lo (.clk(clk), .a_addr(a[15:1]), .a_we(acc_we && sel_vram && cpu_be[0]),
        .a_din(cpu_wdata[7:0]), .a_dout(vram_cq[7:0]), .b_addr(vram_addr), .b_dout(vram_q[7:0]));
    // palette and sprite RAM are write-only for the CPU (MAME: reads 0)
    dnm_sdpram #(.AW(11), .DW(8)) pal_hi (.clk(clk), .w_addr(a[11:1]), .we(acc_we && sel_pal && cpu_be[1]),
        .din(cpu_wdata[15:8]), .r_addr(pal_addr), .dout(pal_q[15:8]));
    dnm_sdpram #(.AW(11), .DW(8)) pal_lo (.clk(clk), .w_addr(a[11:1]), .we(acc_we && sel_pal && cpu_be[0]),
        .din(cpu_wdata[7:0]), .r_addr(pal_addr), .dout(pal_q[7:0]));
    // sprite RAM: words 0-4 of each entry in separate RAMs so the sprite engine reads an entry per
    // clock; words 5-7 are not used by the hardware model and not stored
    genvar w;
    generate
    for (w = 0; w < 5; w = w + 1) begin : spr_words
        dnm_sdpram #(.AW(7), .DW(8)) hi (.clk(clk), .w_addr(a[10:4]),
            .we(acc_we && sel_spr && a[3:1] == w && cpu_be[1]), .din(cpu_wdata[15:8]),
            .r_addr(spr_addr), .dout(spr_q[w*16 + 8 +: 8]));
        dnm_sdpram #(.AW(7), .DW(8)) lo (.clk(clk), .w_addr(a[10:4]),
            .we(acc_we && sel_spr && a[3:1] == w && cpu_be[0]), .din(cpu_wdata[7:0]),
            .r_addr(spr_addr), .dout(spr_q[w*16 +: 8]));
    end
    endgenerate

    // ------------------------------------------------------------------ program ROM cache
    logic        c_lookup, c_hit, c_fill_start, c_fill_done;
    logic [15:0] c_hit_data, c_fill_data;
    dnm_rom_cache cache (
        .clk(clk), .flush(rom_flush),
        .addr(a[19:1]), .lookup(c_lookup), .hit(c_hit), .hit_data(c_hit_data),
        .fill_start(c_fill_start), .fill_done(c_fill_done), .fill_data(c_fill_data),
        .mem_req(rom_req), .mem_addr(rom_addr), .mem_ack(rom_ack), .mem_data(rom_data));

    // ------------------------------------------------------------------ bus backend
    typedef enum logic [2:0] {B_IDLE, B_READ1, B_READ2, B_FILL, B_END} bstate_t;
    bstate_t bst;
    wire  accept = bst == B_IDLE && cpu_req;
    assign acc_we = accept && cpu_write;
    assign c_lookup = bst == B_READ2;

    logic irq_clear;

    always_ff @(posedge clk) begin
        cpu_ack      <= 1'b0;
        snd_latch_wr <= 1'b0;
        host_wr      <= 1'b0;
        irq_clear    <= 1'b0;
        c_fill_start <= 1'b0;
        if (reset) begin
            bst <= B_IDLE;
            coinctrl <= 16'h0000;
            snd_latch <= 8'h00;
            dbg_latch_writes <= '0;
            dbg_misses <= '0;
            for (int i = 0; i < 6; i++) vregs[i] <= 16'h0000;
        end else begin
            case (bst)
                B_IDLE: if (accept) begin
                    if (cpu_write) begin
                        if (sel_io0) begin
                            case (a[3:1])
                                3'd0: begin
                                    if (cpu_be[1] && !b16c) begin                   // C40000
                                        snd_latch    <= cpu_wdata[15:8];
                                        snd_latch_wr <= 1'b1;
                                        dbg_latch_writes <= dbg_latch_writes + 16'd1;
                                    end
                                    if (cpu_be[0] && b16c) begin                    // C40001 OKI
                                        host_wr <= 1'b1; host_sel <= 2'd0; host_data <= cpu_wdata[7:0];
                                    end
                                end
                                3'd1: begin                                         // C40002
                                    if (cpu_be[1]) coinctrl[15:8] <= cpu_wdata[15:8];
                                    if (cpu_be[0]) coinctrl[7:0]  <= cpu_wdata[7:0];
                                end
                                3'd2: irq_clear <= 1'b1;                            // C40004
                                3'd3: if (cpu_be[0] && b16c) begin                  // C40007 OKI bank
                                    host_wr <= 1'b1; host_sel <= 2'd1; host_data <= cpu_wdata[7:0];
                                end
                                3'd4: if (cpu_be[1] && b16c) begin                  // C40008 YM address
                                    host_wr <= 1'b1; host_sel <= 2'd2; host_data <= cpu_wdata[15:8];
                                end
                                3'd5: if (cpu_be[1] && b16c) begin                  // C4000A YM data
                                    host_wr <= 1'b1; host_sel <= 2'd3; host_data <= cpu_wdata[15:8];
                                end
                                default: ;
                            endcase
                        end
                        // video registers live in text RAM: keep a copy for the renderer
                        if (sel_txt && a[11:1] >= 11'h051 && a[11:1] <= 11'h056) begin
                            if (cpu_be[1]) vregs[a[3:1] - 3'd1][15:8] <= cpu_wdata[15:8];
                            if (cpu_be[0]) vregs[a[3:1] - 3'd1][7:0]  <= cpu_wdata[7:0];
                        end
                        cpu_ack <= 1'b1;
                        bst <= B_END;
                    end else
                        bst <= B_READ1;
                end
                B_READ1: bst <= B_READ2;
                B_READ2: begin
                    if (sel_rom && !c_hit) begin
                        c_fill_start <= 1'b1;
                        dbg_misses   <= dbg_misses + 16'd1;
                        bst <= B_FILL;
                    end else begin
                        cpu_rdata <= sel_rom  ? c_hit_data :
                                     sel_ram  ? ram_q :
                                     sel_txt  ? txt_cq :
                                     sel_vram ? vram_cq :
                                     (sel_io0 && a[3:1] == 3'd0 && b16c) ? {8'h00, oki_status} :
                                     (sel_io0 && a[3:1] == 3'd1) ? coinctrl :
                                     (sel_io1 && a[3:1] == 3'd0) ? {8'h00, in_system} :
                                     (sel_io1 && a[3:1] == 3'd1) ? {8'h00, in_p1} :
                                     (sel_io1 && a[3:1] == 3'd2) ? {8'h00, in_p2} :
                                     (sel_io1 && a[3:1] == 3'd5) ? {8'h00, in_dsw} :
                                     16'h0000;                  // unmapped / write-only: 0 (MAME)
                        cpu_ack <= 1'b1;
                        bst <= B_END;
                    end
                end
                B_FILL: if (c_fill_done) begin
                    cpu_rdata <= c_fill_data;
                    cpu_ack   <= 1'b1;
                    bst       <= B_END;
                end
                B_END: if (!cpu_req) bst <= B_IDLE;
                default: bst <= B_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------ IRQ 4 (docs/HARDWARE.md 4)
    // MAME irq4_line_assert at vblank begin, irq_ack_w (C40004) clears it.
    logic irq4;
    always_ff @(posedge clk) begin
        if (reset) begin
            irq4 <= 1'b0;
            dbg_irq <= '0;
            dbg_frames <= '0;
        end else begin
            if (iack_service && iack_level == 3'd4) dbg_irq <= dbg_irq + 16'd1;
            if (vblank_evt) begin
                irq4 <= 1'b1;
                dbg_frames <= dbg_frames + 16'd1;
            end else if (irq_clear)
                irq4 <= 1'b0;
        end
    end
    assign irq_level = irq4 ? 3'd4 : 3'd0;
endmodule
