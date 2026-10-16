// Deniam MiSTer core -- 68000 program ROM cache.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The 1 MB program ROM lives in SDRAM (it does not fit in block RAM next to everything else).
// This direct-mapped cache of 4-word (8-byte, one SDRAM burst) lines sits in front of it:
//   * the lookup RAMs are addressed continuously by the CPU word address, so a hit is answered
//     with the same 2-clock latency as the other block RAMs (no wait state);
//   * a miss fetches the line through the SDRAM arbiter (~10-20 clk_sys) and answers from the fill.
// The valid bits are cleared while a ROM download is in progress (the CPU is held in reset then)
// and are zero after FPGA configuration.
module dnm_rom_cache #(
    parameter int LINES_LOG2 = 13               // 8192 lines x 8 bytes = 64 KB
) (
    input  logic        clk,
    input  logic        flush,                  // ioctl_download: sweep the valid bits

    input  logic [19:1] addr,                   // CPU byte address bits 19..1 (held during a request)
    input  logic        lookup,                 // B_READ2-style strobe: addr has been stable >= 2 clocks
    output logic        hit,                    // with lookup: data valid now
    output logic [15:0] hit_data,

    input  logic        fill_start,             // begin a line fill for addr (after a miss)
    output logic        fill_done,              // one clock: fill_data valid
    output logic [15:0] fill_data,

    output logic        mem_req,
    output logic [25:1] mem_addr,
    input  logic        mem_ack,
    input  logic [63:0] mem_data
);
    localparam int TW = 19 - LINES_LOG2 - 2;    // tag width: addr[19 : LINES_LOG2+3]

    wire [LINES_LOG2-1:0] idx = addr[LINES_LOG2+2:3];
    wire [TW-1:0]         tag = addr[19:LINES_LOG2+3];

    logic [LINES_LOG2-1:0] sweep = '0;
    logic        t_we, d_we;
    logic [LINES_LOG2-1:0] t_waddr;
    logic [TW:0] t_wdata, t_q;                  // {valid, tag}
    logic [63:0] d_q;

    dnm_sdpram #(.AW(LINES_LOG2), .DW(TW + 1)) tags (
        .clk(clk), .w_addr(t_waddr), .we(t_we), .din(t_wdata), .r_addr(idx), .dout(t_q));
    dnm_sdpram #(.AW(LINES_LOG2), .DW(64)) data (
        .clk(clk), .w_addr(idx), .we(d_we), .din(mem_data), .r_addr(idx), .dout(d_q));

    assign hit      = t_q[TW] && t_q[TW-1:0] == tag;
    assign hit_data = d_q[addr[2:1]*16 +: 16];

    always_ff @(posedge clk) begin
        t_we      <= 1'b0;
        d_we      <= 1'b0;
        fill_done <= 1'b0;
        if (flush) begin
            mem_req <= 1'b0;
            sweep   <= sweep + 1'd1;
            t_we    <= 1'b1;
            t_waddr <= sweep;
            t_wdata <= '0;
        end else if (fill_start && !mem_req) begin
            mem_req  <= 1'b1;
            mem_addr <= {6'd0, addr[19:3], 2'b00};
        end else if (mem_req && mem_ack) begin
            mem_req   <= 1'b0;
            d_we      <= 1'b1;
            t_we      <= 1'b1;
            t_waddr   <= idx;
            t_wdata   <= {1'b1, tag};
            fill_done <= 1'b1;
            fill_data <= mem_data[addr[2:1]*16 +: 16];
        end
    end
endmodule
