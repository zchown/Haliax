const std = @import("std");
const brd = @import("board");

// This is unfortunately currently slower then a ray-casting approach for Tak,
// this may change in the future if it can be more tightly integrated with the
// rest of the move generation code. Specificaqlly, if we can tie in sympathy.

pub const max_slide_mask_bits: usize = 2 * (brd.board_size - 1);
pub const max_slide_table_entries: usize = 1 << max_slide_mask_bits;

pub const slide_dir_masks: [brd.num_squares][4]brd.Bitboard = blk: {
    @setEvalBranchQuota(1000000000);
    var arr: [brd.num_squares][4]brd.Bitboard = undefined;
    for (0..brd.num_squares) |sq| {
        const p: brd.Position = @as(brd.Position, @intCast(sq));
        arr[sq][@intFromEnum(brd.Direction.North)] = slideDirMask(p, .North);
        arr[sq][@intFromEnum(brd.Direction.South)] = slideDirMask(p, .South);
        arr[sq][@intFromEnum(brd.Direction.East)]  = slideDirMask(p, .East);
        arr[sq][@intFromEnum(brd.Direction.West)]  = slideDirMask(p, .West);
    }
    break :blk arr;
};

pub const slide_masks: [brd.num_squares]brd.Bitboard = blk: {
    @setEvalBranchQuota(1000000000);
    var arr: [brd.num_squares]brd.Bitboard = undefined;
    for (0..brd.num_squares) |sq| {
        const p: brd.Position = @as(brd.Position, @intCast(sq));
        arr[sq] = slideMask(p);
    }
    break :blk arr;
};

pub const slide_attacks: [brd.num_squares][max_slide_table_entries]brd.Bitboard = blk: {
    @setEvalBranchQuota(1000000000);
    var table: [brd.num_squares][max_slide_table_entries]brd.Bitboard = undefined;

    for (0..brd.num_squares) |sq| {
        const pos: brd.Position = @as(brd.Position, @intCast(sq));
        const mask = slide_masks[sq];
        const bits = countMaskBits(mask);

        const fixed_positions = buildBitPositions(mask);
        const mask_bits = fixed_positions[0..bits];

        const entries: usize = (@as(usize, 1) << bits);

        for (0..max_slide_table_entries) |i| table[sq][i] = 0;

        for (0..entries) |i| {
            const blockers = blockersFromIndex(mask_bits, i);
            table[sq][i] = slideReachableWithBlockers(pos, blockers);
        }
    }

    break :blk table;
};

pub inline fn slideReachable(board: *const brd.Board, pos: brd.Position) brd.Bitboard {
    const blockers: brd.Bitboard = (board.standing_stones | board.capstones);
    const mask = slide_masks[@as(usize, @intCast(pos))];
    const relevant = blockers & mask;

    const idx: u16 = compressMaskToIndex(mask, relevant);
    return slide_attacks[@as(usize, @intCast(pos))][@as(usize, idx)];
}

pub inline fn numStepsMagic(board: *const brd.Board, pos: brd.Position, dir: brd.Direction) usize {
    const reachable = slideReachable(board, pos);
    const dir_mask = slide_dir_masks[@as(usize, @intCast(pos))][@intFromEnum(dir)];
    return @as(usize, @intCast(@popCount(reachable & dir_mask)));
}

pub inline fn compressMaskToIndex(mask: brd.Bitboard, value: brd.Bitboard) u16 {
    var idx: u16 = 0;
    var bit: u4 = 0;
    var m = mask;
    while (m != 0) : (bit += 1) {
        const lsb: u6 = @as(u6, @intCast(@ctz(m)));
        if ((value & brd.getPositionBB(lsb)) != 0) {
            idx |= (@as(u16, 1) << bit);
        }
        m &= (m - 1);
    }
    return idx;
}


fn slideDirMask(pos: brd.Position, dir: brd.Direction) brd.Bitboard {
    var bb: brd.Bitboard = 0;
    var cur: ?brd.Position = brd.nextPosition(pos, dir);

    while (cur) |p| {
        bb |= brd.getPositionBB(p);
        cur = brd.nextPosition(p, dir);
    }
    return bb;
}

fn slideMask(pos: brd.Position) brd.Bitboard {
    return slideDirMask(pos, .North) |
        slideDirMask(pos, .East) |
        slideDirMask(pos, .South) |
        slideDirMask(pos, .West);
}


fn countMaskBits(mask: brd.Bitboard) u6 {
    return @as(u6, @intCast(@popCount(mask)));
}

fn buildBitPositions(mask: brd.Bitboard) [max_slide_mask_bits]u6 {
    var positions: [max_slide_mask_bits]u6 = undefined;
    var i: usize = 0;
    var temp_mask = mask;
    while (temp_mask != 0) {
        const lsb = @as(u6, @intCast(@ctz(temp_mask)));
        positions[i] = lsb;
        i += 1;
        temp_mask &= ~brd.getPositionBB(lsb);
    }
    return positions;
}

fn blockersFromIndex(mask_bits: []const u6, index: usize) brd.Bitboard {
    var b: brd.Bitboard = 0;
    for (mask_bits, 0..) |p, k| {
        if (((index >> @as(u6, @intCast(k))) & 1) != 0) {
            b |= brd.getPositionBB(p);
        }
    }
    return b;
}

fn slideReachableWithBlockers(pos: brd.Position, blockers: brd.Bitboard) brd.Bitboard {
    var out: brd.Bitboard = 0;
    const dirs: [4]brd.Direction = .{ .North, .South, .East, .West };

    for (dirs) |dir| {
        var cur = brd.nextPosition(pos, dir);
        while (cur) |p| {
            const bb = brd.getPositionBB(p);
            if ((blockers & bb) != 0) break;
            out |= bb;
            cur = brd.nextPosition(p, dir);
        }
    }
    return out;
}

