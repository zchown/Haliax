const std = @import("std");
const brd = @import("board.zig");

pub const ZobristHash = u64;

const zobrist_table: [brd.num_squares][brd.num_colors][brd.num_piece_types][brd.zobrist_stack_depth]ZobristHash = blk: {
    @setEvalBranchQuota(1000000);
    break :blk initZobristTable();
};

fn splitMix64(key: *u64) u64 {
    key.* = key.* +% 0x9E3779B97F4A7C15;
    var z = key.*;
    z = (z ^ (z >> 30)) *% 0xBF584761CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn initZobristTable() [brd.num_squares][brd.num_colors][brd.num_piece_types][brd.zobrist_stack_depth]ZobristHash {
    var seed: u64 = 0x1234567890ABCDEF;
    var table: [brd.num_squares][brd.num_colors][brd.num_piece_types][brd.zobrist_stack_depth]ZobristHash = undefined;
    for (0..brd.num_squares) |sq| {
        for (0..brd.num_colors) |color| {
            for (0..brd.num_piece_types) |piece_type| {
                for (0..brd.zobrist_stack_depth) |depth| {
                    table[sq][color][piece_type][depth] = splitMix64(&seed);
                }
            }
        }
    }
    return table;
}

pub fn computeZobristHash(board: *brd.Board) void {
    var hash: ZobristHash = 0;

    for (0..brd.num_squares) |sq| {
        const square = board.squares[sq];
        for (0..square.len) |i| {
            const piece = square.stack[i].?;
            const piece_type: usize = switch (piece.stone_type) {
                .Flat => 0,
                .Standing => 1,
                .Capstone => 2,
            };
            const color: usize = switch (piece.color) {
                .White => 0,
                .Black => 1,
            };
            hash ^= zobrist_table[sq][color][piece_type][i];
        }
    }

    board.zobrist_hash = hash;
}

pub fn updateZobristHash(board: *brd.Board, move: brd.Move) void {
    if (move.pattern == 0) {
        const p = brd.Piece{
            .stone_type = @enumFromInt(move.flag),
            .color = board.to_move,
        };
        std.debug.assert(board.squares[move.position].len > 0);
        updateSinglePositionHash(board, move.position, p, board.squares[move.position].len - 1);
    }

    else {
        var pos: brd.Position = @intCast(move.position);
        const direction: brd.Direction = @enumFromInt(move.flag);
        var updates: usize = 0;
        for (0..brd.max_pickup) |i| {
            // the ith bit from the left
            const cur = move.pattern >> (@as(u3, @intCast(brd.max_pickup)) - 1 - @as(u3, @intCast(i))) & 1;
            if (cur == 0) {
                updates += 1;
            }
            else {
                for (0..updates) |j| {
                    const from_depth = board.squares[pos].len - 1 - (updates - 1 - j);
                    const piece = board.squares[pos].stack[from_depth] orelse unreachable;
                    updateSinglePositionHash(board, pos, piece, from_depth);
                }
                pos = brd.nextPosition(pos, direction) orelse unreachable;
                updates = 0;
            }
        }
    }
}

fn updateSinglePositionHash(board: 
    *brd.Board, pos: brd.Position, piece: brd.Piece, depth: usize) void {

    const piece_type: usize = switch (piece.stone_type) {
        .Flat => 0,
        .Standing => 1,
        .Capstone => 2,
    };
    const color: usize = switch (piece.color) {
        .White => 0,
        .Black => 1,
    };
    board.zobrist_hash ^= zobrist_table[pos][color][piece_type][depth];
}
