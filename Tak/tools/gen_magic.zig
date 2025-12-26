const std = @import("std");
const brd = @import("board");

const max_slide_mask_bits: usize = 4 * (brd.board_size - 1);

fn blockersFromIndex(mask_bits: []const u6, index: usize) brd.Bitboard {
    var b: brd.Bitboard = 0;
    for (mask_bits, 0..) |p, k| {
        if (((index >> @as(u6, @intCast(k))) & 1) != 0) {
            b |= brd.getPositionBB(p);
        }
    }
    return b;
}

fn slideMask(pos: brd.Position) brd.Bitboard {
    return slideDirMask(pos, .North) |
        slideDirMask(pos, .East) |
        slideDirMask(pos, .South) |
        slideDirMask(pos, .West);
}

fn slideDirMask(pos: brd.Position, dir: brd.Direction) brd.Bitboard {
    var bb: brd.Bitboard = 0;
    var cur_opt: ?brd.Position = brd.nextPosition(pos, dir);

    while (cur_opt) |cur| {
        const nxt = brd.nextPosition(cur, dir);
        if (nxt == null) break;
        bb |= brd.getPositionBB(cur);
        cur_opt = nxt;
    }
    return bb;
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

const SplitMix64 = struct {
    x: u64,
    pub fn init(seed: u64) SplitMix64 {
        return .{ .x = seed };
    }
    pub fn next(self: *SplitMix64) u64 {
        var z = (self.x +% 0x9E3779B97F4A7C15);
        self.x = z;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return z ^ (z >> 31);
    }
    pub fn nextSparse(self: *SplitMix64) u64 {
        return self.next() & self.next() & self.next();
    }
};

fn buildMaskBits(mask: brd.Bitboard, out: *[max_slide_mask_bits]u6) usize {
    var n: usize = 0;
    var m: u64 = @as(u64, @intCast(mask));
    while (m != 0) {
        const lsb: u6 = @intCast(@ctz(m));
        out[n] = lsb;
        n += 1;
        m &= (m - 1);
    }
    return n;
}

fn findPerfectMagic(
    alloc: std.mem.Allocator,
    pos: brd.Position,
    mask: brd.Bitboard,
    bits: u6,
    seed: u64,
) !u64 {
    if (bits == 0) return 0;

    const entries: usize = @as(usize, 1) << bits;
    const shift: u6 = @intCast(64 - @as(u8, bits));

    var mask_bits_buf: [max_slide_mask_bits]u6 = undefined;
    const n_mask_bits = buildMaskBits(mask, &mask_bits_buf);
    _ = n_mask_bits;

    var occ = try alloc.alloc(u64, entries);
    defer alloc.free(occ);
    var att = try alloc.alloc(brd.Bitboard, entries);
    defer alloc.free(att);
    var used = try alloc.alloc(brd.Bitboard, entries);
    defer alloc.free(used);
    var seen = try alloc.alloc(bool, entries);
    defer alloc.free(seen);

    for (0..entries) |i| {
        const blockers = blockersFromIndex(mask_bits_buf[0..@as(usize, bits)], i);
        occ[i] = @as(u64, @intCast(blockers));
        att[i] = slideReachableWithBlockers(pos, blockers);
    }

    var rng = SplitMix64.init(seed ^ (@as(u64, @intCast(pos)) *% 0xD6E8FEB86659FD93));

    var attempt: usize = 0;
    var min_popcount: u32 = 6;

    while (attempt < 100_000_000) : (attempt += 1) {
        const magic = rng.nextSparse();

        if (attempt > 10_000_000 and min_popcount > 4) {
            min_popcount = 4;
            std.debug.print("    Relaxing filter to {d} bits...\n", .{min_popcount});
        }
        if (attempt > 50_000_000 and min_popcount > 2) {
            min_popcount = 2;
            std.debug.print("    Relaxing filter to {d} bits...\n", .{min_popcount});
        }

        if (@popCount((mask *% magic) & 0xFF00_0000_0000_0000) < min_popcount) continue;

        @memset(seen, false);

        var collision = false;
        for (0..entries) |i| {
            const idx: usize = @intCast((occ[i] *% magic) >> shift);
            const a = att[i];

            if (!seen[idx]) {
                seen[idx] = true;
                used[idx] = a;
            } else if (used[idx] != a) {
                collision = true;
                break;
            }
        }

        if (!collision) {
            if (attempt > 1000) {
                std.debug.print("  Found after {d} attempts\n", .{attempt});
            }
            return magic;
        }

        if (attempt > 0 and attempt % 5_000_000 == 0) {
            std.debug.print("    ...{d}M attempts...\n", .{attempt / 1_000_000});
        }
    }

    std.debug.print("  FAILED after {d} attempts!\n", .{attempt});
    return error.MagicNotFound;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var so = std.fs.File.stdout();
    var stdout_buffer: [2048]u8 = undefined;
    var bw = so.writer(&stdout_buffer);
    var stdout = &bw.interface;

    var masks: [brd.num_squares]brd.Bitboard = undefined;
    var bits_arr: [brd.num_squares]u6 = undefined;
    var shifts: [brd.num_squares]u6 = undefined;
    var offsets: [brd.num_squares]u32 = undefined;

    var total_entries: usize = 0;
    for (0..brd.num_squares) |sq| {
        const pos: brd.Position = @intCast(sq);
        const mask = slideMask(pos);
        masks[sq] = mask;

        const bits: u6 = @intCast(@popCount(mask));
        bits_arr[sq] = bits;

        shifts[sq] = @intCast(64 - @as(u8, bits));

        offsets[sq] = @intCast(total_entries);

        total_entries += (@as(usize, 1) << bits);
    }

    var packed_attacks = try alloc.alloc(brd.Bitboard, total_entries);
    defer alloc.free(packed_attacks);

    var magics: [brd.num_squares]u64 = undefined;

    const start_time = std.time.milliTimestamp();

    for (0..brd.num_squares) |sq| {
        std.debug.print("Square {d}/{d}: ", .{ sq + 1, brd.num_squares });
        const pos: brd.Position = @intCast(sq);
        const mask = masks[sq];
        const bits = bits_arr[sq];
        const entries: usize = @as(usize, 1) << bits;
        const base: usize = offsets[sq];

        const magic = try findPerfectMagic(alloc, pos, mask, bits, 0xC0FFEE123456789B);
        magics[sq] = magic;

        var mask_bits_buf: [max_slide_mask_bits]u6 = undefined;
        _ = buildMaskBits(mask, &mask_bits_buf);

        const shift: u6 = shifts[sq];

        for (0..entries) |i| packed_attacks[base + i] = 0;

        for (0..entries) |i| {
            const blockers = blockersFromIndex(mask_bits_buf[0..@as(usize, bits)], i);
            const attacks = slideReachableWithBlockers(pos, blockers);

            const relevant_u64: u64 = @as(u64, @intCast(blockers));
            const idx: usize = if (bits == 0)
                0
            else
                @intCast((relevant_u64 *% magic) >> shift);

            packed_attacks[base + idx] = attacks;
        }
    }

    const elapsed = std.time.milliTimestamp() - start_time;
    std.debug.print("\nGeneration completed in {d}ms\n", .{elapsed});

    try stdout.writeAll("// AUTO-GENERATED by gen_magic.zig\n");
    try stdout.writeAll("const brd = @import(\"board\");\n\n");

    try stdout.writeAll("pub const slide_magics: [brd.num_squares]u64 = .{\n");
    for (0..brd.num_squares) |sq| {
        try stdout.print("    0x{x},\n", .{magics[sq]});
    }
    try stdout.writeAll("};\n\n");

    try stdout.writeAll("pub const slide_masks: [brd.num_squares]brd.Bitboard = .{\n");
    for (0..brd.num_squares) |sq| {
        try stdout.print("    0x{x},\n", .{@as(u64, @intCast(masks[sq]))});
    }
    try stdout.writeAll("};\n\n");

    try stdout.writeAll("pub const slide_shifts: [brd.num_squares]u6 = .{\n");
    for (0..brd.num_squares) |sq| {
        try stdout.print("    {d},\n", .{shifts[sq]});
    }
    try stdout.writeAll("};\n\n");

    try stdout.writeAll("pub const slide_offsets: [brd.num_squares]u32 = .{\n");
    for (0..brd.num_squares) |sq| {
        try stdout.print("    {d},\n", .{offsets[sq]});
    }
    try stdout.writeAll("};\n\n");

    try stdout.print("pub const slide_total_entries: usize = {d};\n\n", .{total_entries});

    try stdout.writeAll("pub const slide_attacks_packed: [slide_total_entries]brd.Bitboard = .{\n");
    for (0..total_entries) |i| {
        try stdout.print("    0x{x},\n", .{@as(u64, @intCast(packed_attacks[i]))});
    }
    try stdout.writeAll("};\n");
    try stdout.flush();
}

