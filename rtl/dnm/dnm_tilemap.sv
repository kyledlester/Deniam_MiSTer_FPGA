// Deniam MiSTer core -- tilemap line renderer (BG, FG, text).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// docs/HARDWARE.md 6.2-6.5. On `start` it renders the 320 visible pixels (board x 188..507) of
// line y for BG, then FG, then the text layer, into three line buffers:
//   BG {colour[6:0], pen[2:0]}, FG {colour[6:0], pen[2:0]} (pen 0 = transparent), TX {colour[2:0], pen[2:0]}.
// Per layer 41 tiles are fetched (8-pixel aligned in tilemap space, the first one partly left of
// the window). A tile = 1 attribute read from tilemap/text RAM + 1 SDRAM burst (dnm_loader.sv:
// words {tile, row[2:1], plane} hold rows r, r+1 of planes ROM1, ROM2, ROM3). A separate writer
// puts the 8 pixels of a fetched tile into the line buffer while the next tile is fetched.
module dnm_tilemap (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,
    input  logic   [7:0] y,             // board line 0..223
    input  logic   [9:0] bg_sx,         // effective scroll (offsets applied, dnm_video.sv)
    input  logic   [7:0] bg_sy,
    input  logic  [15:0] bg_pages,
    input  logic   [9:0] fg_sx,
    input  logic   [7:0] fg_sy,
    input  logic  [15:0] fg_pages,
    output logic         busy,

    output logic  [14:0] vram_addr,
    input  logic  [15:0] vram_q,
    output logic  [10:0] txt_addr,
    input  logic  [15:0] txt_q,

    output logic         mem_req,
    output logic  [25:1] mem_addr,
    input  logic         mem_ack,
    input  logic  [63:0] mem_data,

    output logic   [2:0] lb_we,         // BG, FG, TX
    output logic   [8:0] lb_x,          // 0..319
    output logic   [9:0] lb_data
);
    typedef enum logic [2:0] {S_IDLE, S_ADDR, S_WAIT, S_ATTR, S_FETCH, S_HAND, S_DRAIN} st_t;
    st_t st;
    logic [1:0]  layer;                 // 0 BG, 1 FG, 2 TX
    logic [5:0]  tile_i;                // 0..40
    logic [9:0]  tx0;                   // tilemap x of the window's first pixel
    logic [8:0]  ty;                    // tilemap y
    logic [15:0] pages;
    logic [15:0] attr;
    logic [6:0]  colour;
    logic [63:0] tdata;

    // tilemap x of tile i (aligned)
    wire [9:0] tcol_x = {tx0[9:3], 3'b000} + {1'b0, tile_i, 3'b000};
    wire [6:0] col = tcol_x[9:3];
    wire [5:0] row = ty[8:3];
    wire [1:0] tpage = {row[5], col[6]};
    wire [3:0] vpage = pages[tpage*4 +: 4];

    // ------------------------------------------------------------------ writer
    logic        w_busy;
    logic [3:0]  w_k;
    logic [1:0]  w_layer;
    logic [23:0] w_bits;                // {ROM3, ROM2, ROM1} row bytes, bit 7 = left pixel
    logic [6:0]  w_colour;
    logic [9:0]  w_d0;                  // signed-ish: line-buffer position of pixel 0 (+ 8 offset)
    logic        hand;                  // fetcher hands a tile to the writer (one clock)

    always_ff @(posedge clk) begin
        lb_we <= '0;
        if (rst) begin
            w_busy <= 1'b0;
        end else if (hand) begin
            w_busy   <= 1'b1;
            w_k      <= '0;
            w_layer  <= layer;
            w_colour <= colour;
            w_bits   <= ty[0] ? {tdata[39:32], tdata[23:16], tdata[7:0]}
                              : {tdata[47:40], tdata[31:24], tdata[15:8]};
            w_d0     <= {tile_i, 3'b000} - {7'd0, tx0[2:0]} + 10'd8;   // +8: pixel 0 of tile 0 may be < 0
        end else if (w_busy) begin
            logic [2:0] pen, b;
            logic [9:0] d;
            b   = 3'd7 - w_k[2:0];                          // bit 7 = left pixel
            pen = {w_bits[{2'd2, b}], w_bits[{2'd1, b}], w_bits[{2'd0, b}]};
            d   = w_d0 + {6'd0, w_k};
            if (d >= 10'd8 && d < 10'd328) begin
                lb_we[w_layer] <= 1'b1;
                lb_x    <= 9'(d - 10'd8);
                lb_data <= (w_layer == 2'd2) ? {4'd0, w_colour[2:0], pen} : {w_colour, pen};
            end
            w_k <= w_k + 4'd1;
            if (w_k == 4'd7) w_busy <= 1'b0;
        end
    end

    // ------------------------------------------------------------------ fetcher
    assign busy = st != S_IDLE;

    always_ff @(posedge clk) begin
        hand <= 1'b0;
        if (rst) begin
            st <= S_IDLE;
            mem_req <= 1'b0;
        end else case (st)
            S_IDLE: if (start) begin
                layer  <= 2'd0;
                tile_i <= '0;
                tx0    <= 10'd188 + bg_sx;
                ty     <= {1'b0, y} + {1'b0, bg_sy};
                pages  <= bg_pages;
                st     <= S_ADDR;
            end
            S_ADDR: begin
                vram_addr <= {vpage, row[4:0], col[5:0]};
                txt_addr  <= {row[4:0], col[5:0]};
                st <= S_WAIT;
            end
            S_WAIT: st <= S_ATTR;
            S_ATTR: begin
                logic [15:0] at, code;
                at = (layer == 2'd2) ? txt_q : vram_q;
                code = (layer == 2'd2) ? (at & 16'hF1FF) : at;
                colour   <= (layer == 2'd2) ? {4'd0, at[11:9]} : at[12:6];
                mem_req  <= 1'b1;
                mem_addr <= 25'h080000 + {5'd0, code, ty[2:1], 2'b00};
                st <= S_FETCH;
            end
            S_FETCH: if (mem_ack) begin
                mem_req <= 1'b0;
                tdata   <= mem_data;
                st      <= S_HAND;
            end
            S_HAND: if (!w_busy) begin
                hand <= 1'b1;
                st   <= S_DRAIN;
            end
            S_DRAIN: begin                                  // writer has latched the tile
                if (tile_i != 6'd40) begin
                    tile_i <= tile_i + 6'd1;
                    st <= S_ADDR;
                end else if (layer == 2'd0) begin
                    layer  <= 2'd1;
                    tile_i <= '0;
                    tx0    <= 10'd188 + fg_sx;
                    ty     <= {1'b0, y} + {1'b0, fg_sy};
                    pages  <= fg_pages;
                    st     <= S_ADDR;
                end else if (layer == 2'd1) begin
                    layer  <= 2'd2;
                    tile_i <= '0;
                    tx0    <= 10'd188;                      // text layer: not scrolled, 64 x 32
                    ty     <= {1'b0, y};
                    pages  <= 16'h0000;
                    st     <= S_ADDR;
                end else if (!w_busy)
                    st <= S_IDLE;
            end
            default: st <= S_IDLE;
        endcase
    end
endmodule
