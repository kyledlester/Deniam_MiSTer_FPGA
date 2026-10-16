// Deniam MiSTer core -- sprite line renderer.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// docs/HARDWARE.md 6.6 (MAME deniamc_state::draw_sprites). On `start` it walks the 128 entries from
// 127 down to 0; for every entry covering line y (start Y < y <= end Y) it streams that row's
// nibbles from the sprite ROM (SDRAM, 8 bytes per burst, cached as one block) at one nibble per
// clock. Every non-transparent nibble inside the visible window claims its pixel: the first claim
// (highest entry number) writes {1, priority, colour, pen} into the line buffer, later ones are
// dropped. The row ends at the second F nibble, after 512 bytes, or once the pixel position is past
// the window (x only grows, in both directions of the ROM walk).
module dnm_sprites (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,
    input  logic   [7:0] y,
    output logic         busy,

    output logic   [6:0] spr_addr,
    input  logic  [79:0] spr_q,         // words 4..0

    output logic         mem_req,
    output logic  [25:1] mem_addr,
    input  logic         mem_ack,
    input  logic  [63:0] mem_data,

    output logic         lb_we,
    output logic   [8:0] lb_x,
    output logic  [12:0] lb_data        // {1, pri[1:0], colour[5:0], pen[3:0]}
);
    typedef enum logic [2:0] {S_IDLE, S_RD, S_WAIT, S_ENTRY, S_ROW, S_FETCH, S_NEXT} st_t;
    st_t st;
    logic [6:0]   e;
    logic [319:0] claimed;

    logic [21:0]  bp;                   // sprite ROM byte pointer
    logic         flip;
    logic         nib2;                 // second nibble of the current byte
    logic         seen;                 // first F seen
    logic [9:0]   nbytes;
    logic [10:0]  px;                   // board x of the next pixel
    logic [1:0]   pri;
    logic [5:0]   colour;
    logic [18:0]  blk_tag;
    logic         blk_ok;
    logic [63:0]  blk;

    assign busy = st != S_IDLE;

    // current byte from the cached block: word k = {byte 2k, byte 2k+1}
    wire [15:0] bw   = blk[bp[2:1]*16 +: 16];
    wire [7:0]  byt  = bp[0] ? bw[7:0] : bw[15:8];
    // normal order: high nibble first; flip X: low nibble first
    wire [3:0]  nib  = (nib2 ^ flip) ? byt[3:0] : byt[7:4];
    wire        hit  = blk_ok && blk_tag == bp[21:3];
    wire        in_win = px >= 11'd188 && px <= 11'd507;
    wire [8:0]  d    = 9'(px - 11'd188);

    always_ff @(posedge clk) begin
        lb_we <= 1'b0;
        if (rst) begin
            st <= S_IDLE;
            mem_req <= 1'b0;
            blk_ok <= 1'b0;
        end else case (st)
            S_IDLE: if (start) begin
                claimed <= '0;
                e  <= 7'd127;
                st <= S_RD;
            end
            S_RD: begin
                spr_addr <= e;
                st <= S_WAIT;
            end
            S_WAIT: st <= S_ENTRY;
            S_ENTRY: begin
                logic [7:0]  sy, ey, r;
                logic [14:0] wr;
                logic [9:0]  sx;
                logic [20:0] wa;
                sy = spr_q[7:0];
                ey = spr_q[15:8];
                r  = y - sy;
                sx = {1'b0, spr_q[24:16]} + 10'd127;
                if (sx >= 10'd512) sx = sx - 10'd512;
                if (spr_q[40]) sx = sx + 10'd1;
                wr = {8'd0, spr_q[38:32]} * {7'd0, r};
                wa = {spr_q[76:72], spr_q[63:48]} + {6'd0, wr};
                flip   <= spr_q[40];
                px     <= {1'b0, sx};
                colour <= spr_q[69:64];
                pri    <= spr_q[71:70];
                bp     <= {wa, 1'b0};
                nib2   <= 1'b0;
                seen   <= 1'b0;
                nbytes <= '0;
                st <= (y > sy && y <= ey) ? S_ROW : S_NEXT;
            end
            S_ROW: begin
                if (!hit) begin
                    mem_req  <= 1'b1;
                    mem_addr <= 25'h180000 + {4'd0, bp[21:3], 2'b00};
                    st <= S_FETCH;
                end else begin
                    logic done;
                    done = 1'b0;
                    if (nib == 4'hF) begin
                        if (seen) done = 1'b1;
                        seen <= 1'b1;
                    end else begin
                        if (nib != 4'h0 && in_win && !claimed[d]) begin
                            claimed[d] <= 1'b1;
                            lb_we   <= 1'b1;
                            lb_x    <= d;
                            lb_data <= {1'b1, pri, colour, nib};
                        end
                        px <= px + 11'd1;
                        if (px >= 11'd507) done = 1'b1;   // x only grows: nothing more can be drawn
                    end
                    nib2 <= !nib2;
                    if (nib2) begin
                        bp     <= flip ? bp - 22'd1 : bp + 22'd1;
                        nbytes <= nbytes + 10'd1;
                        if (nbytes == 10'd511) done = 1'b1;
                    end
                    if (done) st <= S_NEXT;
                end
            end
            S_FETCH: if (mem_ack) begin
                mem_req <= 1'b0;
                blk     <= mem_data;
                blk_tag <= bp[21:3];
                blk_ok  <= 1'b1;
                st      <= S_ROW;
            end
            S_NEXT: begin
                if (e == 7'd0) st <= S_IDLE;
                else begin
                    e  <= e - 7'd1;
                    st <= S_RD;
                end
            end
            default: st <= S_IDLE;
        endcase
    end
endmodule
