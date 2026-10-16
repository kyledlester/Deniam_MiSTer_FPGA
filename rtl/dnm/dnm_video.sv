// Deniam MiSTer core -- video: line renderers, line buffers, mixer, palette lookup.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// During raster line v the tilemap and sprite engines render board line v+1 (0..223) into the
// line-buffer half selected by (v+1)[0]; the output side reads half v[0] (and clears the sprite
// entries it has read). The video registers (scroll, pages; text RAM words 0x51-0x56) and the
// display enable (C40002 bit 5) are latched once per frame, when line 0 starts rendering, the way
// MAME applies them per frame. The game's scroll offsets (docs/HARDWARE.md 6.3) are subtracted
// here. "Flipped" (OSD) mirrors the picture: display line d shows board line 223 - d and display
// dot x board dot 319 - x.
// Output pipeline per dot (16 clk_sys): line buffers -> mixer -> palette -> RGB; the output is one
// dot late relative to the raster counters, blank/sync are delayed with it.
module dnm_video (
    input  logic         clk,
    input  logic         rst,
    input  logic         ce_pix,
    input  logic   [8:0] hcount,
    input  logic   [8:0] vcount,
    input  logic         line_start,
    input  logic         hblank_in,
    input  logic         vblank_in,
    input  logic         hsync_in,
    input  logic         vsync_in,

    input  logic         karianx,       // scroll offsets: 0 = logicpro set, 1 = karianx set
    input  logic  [15:0] vregs [6],     // FG X, BG X, FG Y, BG Y, FG pages, BG pages
    input  logic  [15:0] coinctrl,
    input  logic         osd_flip,

    output logic  [14:0] vram_addr,
    input  logic  [15:0] vram_q,
    output logic  [10:0] txt_addr,
    input  logic  [15:0] txt_q,
    output logic  [10:0] pal_addr,
    input  logic  [15:0] pal_q,
    output logic   [6:0] spr_addr,
    input  logic  [79:0] spr_q,

    output logic         tm_req,
    output logic  [25:1] tm_addr,
    input  logic         tm_ack,
    output logic         sp_req,
    output logic  [25:1] sp_addr,
    input  logic         sp_ack,
    input  logic  [63:0] mem_data,

    output logic  [23:0] rgb,
    output logic         hblank,
    output logic         vblank,
    output logic         hsync,
    output logic         vsync,

    output logic  [15:0] dbg_overruns
);
    // ------------------------------------------------------------------ render start
    wire [8:0] next_line = (vcount == 9'd261) ? 9'd0 : vcount + 9'd1;   // vcount is the new line at line_start
    logic      render_start, render_pend, abort;
    logic [7:0] render_y;
    logic      render_half;
    logic      tm_busy, sp_busy;

    logic        mirror = 1'b0;
    logic  [9:0] bg_sx, fg_sx;
    logic  [7:0] bg_sy, fg_sy;
    logic [15:0] bg_pages, fg_pages;
    logic        disp_en = 1'b0, disp_en_out = 1'b0;

    always_ff @(posedge clk) begin
        render_start <= 1'b0;
        abort        <= 1'b0;
        render_pend  <= 1'b0;
        if (rst) begin
            dbg_overruns <= '0;
            disp_en <= 1'b0;
        end else begin
            if (line_start && next_line < 9'd224) begin
                if (tm_busy || sp_busy) begin
                    dbg_overruns <= dbg_overruns + 16'd1;
                    abort <= 1'b1;
                end
                if (next_line == 9'd0) begin
                    logic [9:0] bxo, fxo;
                    logic [7:0] yo;
                    bxo = karianx ? 10'h10D : 10'h00D;
                    fxo = karianx ? 10'h109 : 10'h009;
                    yo  = karianx ? 8'h80 : 8'h00;
                    bg_sx    <= {1'b0, 9'(vregs[1][8:0] - bxo[8:0])};
                    fg_sx    <= {1'b0, 9'(vregs[0][8:0] - fxo[8:0])};
                    bg_sy    <= vregs[3][7:0] - yo;
                    fg_sy    <= vregs[2][7:0] - yo;
                    fg_pages <= vregs[4];
                    bg_pages <= vregs[5];
                    disp_en  <= coinctrl[5];
                    mirror   <= osd_flip;
                end
                render_pend <= 1'b1;
                render_y    <= (next_line == 9'd0 ? osd_flip : mirror) ? 8'd223 - next_line[7:0] : next_line[7:0];
                render_half <= next_line[0];
            end
            render_start <= render_pend;
        end
        // the output side switches with the frame too
        if (line_start && vcount == 9'd0) disp_en_out <= disp_en;
    end

    // ------------------------------------------------------------------ engines
    logic [2:0]  tlb_we;
    logic [8:0]  tlb_x;
    logic [9:0]  tlb_data;
    dnm_tilemap tilemap (
        .clk(clk), .rst(rst || abort), .start(render_start), .y(render_y),
        .bg_sx(bg_sx), .bg_sy(bg_sy), .bg_pages(bg_pages), .fg_sx(fg_sx), .fg_sy(fg_sy), .fg_pages(fg_pages),
        .busy(tm_busy),
        .vram_addr(vram_addr), .vram_q(vram_q), .txt_addr(txt_addr), .txt_q(txt_q),
        .mem_req(tm_req), .mem_addr(tm_addr), .mem_ack(tm_ack), .mem_data(mem_data),
        .lb_we(tlb_we), .lb_x(tlb_x), .lb_data(tlb_data));

    logic        slb_we;
    logic [8:0]  slb_x;
    logic [12:0] slb_data;
    dnm_sprites sprites (
        .clk(clk), .rst(rst || abort), .start(render_start), .y(render_y), .busy(sp_busy),
        .spr_addr(spr_addr), .spr_q(spr_q),
        .mem_req(sp_req), .mem_addr(sp_addr), .mem_ack(sp_ack), .mem_data(mem_data),
        .lb_we(slb_we), .lb_x(slb_x), .lb_data(slb_data));

    // ------------------------------------------------------------------ line buffers
    // port A: output side (read; sprites also cleared), port B: renderer (write)
    wire        wr_half = render_half;
    wire        rd_half = vcount[0];
    logic [8:0] rd_x;
    logic       clr;
    logic [9:0] bq, fq, tq;
    logic [12:0] sq;

    dnm_tdpram #(.AW(10), .DW(10)) lb_bg (.clk(clk),
        .a_addr({rd_half, rd_x}), .a_we(1'b0), .a_din(10'd0), .a_dout(bq),
        .b_addr({wr_half, tlb_x}), .b_we(tlb_we[0]), .b_din(tlb_data));
    dnm_tdpram #(.AW(10), .DW(10)) lb_fg (.clk(clk),
        .a_addr({rd_half, rd_x}), .a_we(1'b0), .a_din(10'd0), .a_dout(fq),
        .b_addr({wr_half, tlb_x}), .b_we(tlb_we[1]), .b_din(tlb_data));
    dnm_tdpram #(.AW(10), .DW(10)) lb_tx (.clk(clk),
        .a_addr({rd_half, rd_x}), .a_we(1'b0), .a_din(10'd0), .a_dout(tq),
        .b_addr({wr_half, tlb_x}), .b_we(tlb_we[2]), .b_din(tlb_data));
    dnm_tdpram #(.AW(10), .DW(13)) lb_sp (.clk(clk),
        .a_addr({rd_half, rd_x}), .a_we(clr), .a_din(13'd0), .a_dout(sq),
        .b_addr({wr_half, slb_x}), .b_we(slb_we), .b_din(slb_data));

    // ------------------------------------------------------------------ mixer (docs/HARDWARE.md 6.6)
    function automatic [10:0] mix(input [12:0] s, input [9:0] f, input [9:0] b, input [9:0] t);
        logic to, fo, sv;
        to = t[2:0] != 3'd0;
        fo = f[2:0] != 3'd0;
        case (s[11:10])
            2'd3:    sv = s[12];
            2'd2:    sv = s[12] && !to;
            2'd1:    sv = s[12] && !to && !fo;
            default: sv = 1'b0;                 // "below everything": hidden by the opaque BG
        endcase
        if (sv)      mix = {1'b1, s[9:0]};      // 1024 + colour * 16 + pen
        else if (to) mix = {5'd0, t[5:0]};
        else if (fo) mix = {1'b0, f};
        else         mix = {1'b0, b};
    endfunction

    // ------------------------------------------------------------------ output pipeline
    // ph 0 (ce_pix): rd_x; 2: line-buffer data -> mixer -> palette address; 4: palette data -> colour.
    logic [3:0]  ph;
    logic        vis_d1, vis_d2;
    logic [23:0] rgb_next;
    logic        hb_d, vb_d, hs_d, vs_d;

    function automatic [7:0] c5(input [4:0] v); c5 = {v, v[4:2]}; endfunction

    always_ff @(posedge clk) begin
        clr <= 1'b0;
        if (ce_pix) begin
            rd_x   <= mirror ? 9'd319 - hcount : hcount;
            ph     <= 4'd1;
            vis_d1 <= !hblank_in && !vblank_in;
            rgb    <= rgb_next;
            {hblank, vblank, hsync, vsync} <= {hb_d, vb_d, hs_d, vs_d};
            {hb_d, vb_d, hs_d, vs_d} <= {hblank_in, vblank_in, hsync_in, vsync_in};
        end else if (ph != 0) begin
            ph <= ph + 4'd1;
            case (ph)
                4'd2: begin
                    pal_addr <= mix(sq, fq, bq, tq);
                    vis_d2 <= vis_d1;
                    clr    <= vis_d1;
                end
                4'd4: begin
                    logic [15:0] p;
                    p = pal_q;
                    if (!vis_d2 || !disp_en_out) rgb_next <= 24'h000000;
                    else rgb_next <= {c5({p[3:0], p[12]}), c5({p[7:4], p[13]}), c5({p[11:8], p[14]})};
                    ph <= 4'd0;
                end
                default: ;
            endcase
        end
    end
endmodule
