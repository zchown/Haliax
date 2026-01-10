const std = @import("std");
const brd = @import("board");
const tracy = @import("tracy");
const gen = @import("magic_bitboards.zig");

pub const slide_dir_masks: [brd.num_squares][4]brd.Bitboard = blk: {
    @setEvalBranchQuota(1_000_000_000);
    var arr: [brd.num_squares][4]brd.Bitboard = undefined;
    for (0..brd.num_squares) |sq| {
        const p: brd.Position = @as(brd.Position, @intCast(sq));
        arr[sq][@intFromEnum(brd.Direction.North)] = slideDirMaskAll(p, .North);
        arr[sq][@intFromEnum(brd.Direction.South)] = slideDirMaskAll(p, .South);
        arr[sq][@intFromEnum(brd.Direction.East)]  = slideDirMaskAll(p, .East);
        arr[sq][@intFromEnum(brd.Direction.West)]  = slideDirMaskAll(p, .West);
    }
    break :blk arr;
};

pub fn slideReachable(board: *const brd.Board, pos: brd.Position) brd.Bitboard {
    const blockers: brd.Bitboard = (board.standing_stones | board.capstones);

    const sq: usize = @as(usize, @intCast(pos));
    const mask: brd.Bitboard = gen.slide_masks[sq];
    const relevant: brd.Bitboard = blockers & mask;

    const idx: usize =
        @intCast((@as(u64, relevant) *% gen.slide_magics[sq]) >> gen.slide_shifts[sq]);

    return gen.slide_attacks_packed[@as(usize, gen.slide_offsets[sq]) + idx] & ~blockers;
}

pub fn numSteps(board: *const brd.Board, pos: brd.Position, dir: brd.Direction) usize {
    const reachable = slideReachable(board, pos);
    const dir_mask = slide_dir_masks[@as(usize, @intCast(pos))][@intFromEnum(dir)];
    return @as(usize, @intCast(@popCount(reachable & dir_mask)));
}

fn slideDirMaskAll(pos: brd.Position, dir: brd.Direction) brd.Bitboard {
    var bb: brd.Bitboard = 0;
    var cur: ?brd.Position = brd.nextPosition(pos, dir);
    while (cur) |p| {
        bb |= brd.getPositionBB(p);
        cur = brd.nextPosition(p, dir);
    }
    return bb;
}

