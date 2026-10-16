// Deniam MiSTer core -- ROM loader (ioctl index 0, hps_io WIDE=1).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Stream layout: docs/MRA_FORMAT.md (scripts/romtool.py is the executable form). ioctl_dout of a
// word region is the big-endian word {region byte 2k, region byte 2k+1}; of a byte region
// {stream byte 2k+1, stream byte 2k}.
//   stream 000000-0FFFFF maincpu  words -> SDRAM word 000000 + k (as is)
//   stream 100000-27FFFF chars    bytes -> SDRAM word 080000 + {tile, row[2:1], plane}:
//                                         word = {row r byte, row r+1 byte} of that plane
//                                         (one 4-word burst = 3 planes x 2 rows of a tile)
//   stream 280000-67FFFF sprites  words -> SDRAM word 180000 + k (as is)
//   stream 680000-77FFFF oki      bytes -> SDRAM word 380000 + k (byte 2k in bits 7-0)
//   stream 780000-78FFFF audiocpu bytes -> Z80 block RAM (deniam-16b only)
// ioctl_wait is held from ioctl_wr until the write is done. `loaded` rises at the end of the
// first download of index 0.
module dnm_loader (
    input  logic        clk,
    input  logic        rst,

    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [15:0] ioctl_dout,
    output logic        ioctl_wait,

    output logic        mem_req,
    output logic [25:1] mem_addr,
    output logic [15:0] mem_wdata,
    input  logic        mem_ack,

    output logic        romz80_we,
    output logic [15:0] romz80_addr,
    output logic  [7:0] romz80_data,

    output logic        loaded
);
    typedef enum logic [1:0] {IDLE, W1, W2, Z2} st_t;
    st_t st;
    logic [26:0] a;
    logic [15:0] d;
    logic        dl_d;

    wire sel = ioctl_download && ioctl_index == 16'd0;
    assign ioctl_wait = st != IDLE;

    always_ff @(posedge clk) begin
        romz80_we <= 1'b0;
        if (rst) begin
            st <= IDLE;
            mem_req <= 1'b0;
            loaded <= 1'b0;
            dl_d <= 1'b0;
        end else begin
            dl_d <= sel;
            if (dl_d && !sel) loaded <= 1'b1;
            case (st)
            IDLE: if (sel && ioctl_wr) begin
                a  <= ioctl_addr;
                d  <= ioctl_dout;
                st <= W1;
            end
            W1: begin
                logic [20:0] o;
                o = '0;
                mem_wdata <= d;
                mem_req   <= 1'b1;
                st        <= W2;
                if (a < 27'h100000)
                    mem_addr <= {5'd0, a[19:1]};
                else if (a < 27'h280000) begin
                    o = 21'(a - 27'h100000);
                    mem_addr  <= 25'h080000 + {5'd0, o[18:3], o[2:1], o[20:19]};
                    mem_wdata <= {d[7:0], d[15:8]};
                end else if (a < 27'h680000)
                    mem_addr <= 25'h180000 + 25'((a - 27'h280000) >> 1);
                else if (a < 27'h780000)
                    mem_addr <= 25'h380000 + 25'((a - 27'h680000) >> 1);
                else if (a < 27'h790000) begin
                    mem_req     <= 1'b0;
                    romz80_we   <= 1'b1;
                    romz80_addr <= {a[15:1], 1'b0};
                    romz80_data <= d[7:0];
                    st          <= Z2;
                end else begin
                    mem_req <= 1'b0;
                    st      <= IDLE;
                end
            end
            W2: if (mem_ack) begin
                mem_req <= 1'b0;
                st      <= IDLE;
            end
            Z2: begin
                romz80_we   <= 1'b1;
                romz80_addr <= {a[15:1], 1'b1};
                romz80_data <= d[15:8];
                st          <= IDLE;
            end
            default: st <= IDLE;
            endcase
        end
    end
endmodule
