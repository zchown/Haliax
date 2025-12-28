const std = @import("std");
const sym = @import("sympathy");
const brd = @import("board");
const testing = std.testing;

// --- Helpers ---------------------------------------------------------------

fn msbIndex(v: u8) u3 {
    // v is always non-zero in our use.
    return @intCast(7 - @clz(v));
}

fn nCk(n: usize, k: usize) u64 {
    if (k > n) return 0;
    if (k == 0 or k == n) return 1;

    var kk: usize = k;
    if (kk > n - kk) kk = n - kk;

    // Compute multiplicatively to avoid intermediate overflow (n is tiny here).
    var res: u64 = 1;
    var i: usize = 1;
    while (i <= kk) : (i += 1) {
        // res *= (n - kk + i) / i
        res = (res * @as(u64, @intCast(n - kk + i))) / @as(u64, @intCast(i));
    }
    return res;
}

fn expectedPatternCount(pickup: usize, max_length: usize) u64 {
    const max_moves: usize = if (max_length > 0) max_length - 1 else 0;
    var total: u64 = 0;
    for (1..pickup + 1) |k| {
        const decisions: usize = k - 1;
        const upto: usize = @min(decisions, max_moves);
        for (0..upto + 1) |j| total += nCk(decisions, j);
    }
    return total;
}

fn expectedCrushCount(pickup: usize, max_length: usize) u64 {
    if (max_length == 0) return 0;
    const required_moves: usize = max_length - 1;

    var total: u64 = 0;
    for (max_length..pickup + 1) |k| {
        const decisions: usize = k - 1;
        if (required_moves == 0) {
            // Only k==1 can satisfy (value & 1) != 0 when mask has popcount 0.
            if (k == 1) total += 1;
            continue;
        }
        // bit0 is forced to 1, so choose the remaining (required_moves-1) ones
        // from the remaining (decisions-1) bits.
        if (decisions >= 1) total += nCk(decisions - 1, required_moves - 1);
    }
    return total;
}

fn assertStrictlyIncreasing(pats: []const u8) !void {
    for (1..pats.len) |i| {
        try testing.expect(pats[i - 1] < pats[i]);
    }
}

fn assertAllDistinct(pats: []const u8) !void {
    // pats are small; O(n^2) is fine and gives better failure locality.
    for (0..pats.len) |i| {
        for (i + 1..pats.len) |j| {
            try testing.expect(pats[i] != pats[j]);
        }
    }
}

fn assertPatternSliceValid(pickup: usize, max_length: usize, pats: []const u8) !void {
    try testing.expect(pickup >= 1 and pickup <= brd.max_pickup);
    try testing.expect(max_length >= 1 and max_length <= brd.max_pickup);

    // Structural invariants of generatePatternsForConfig.
    const max_moves: usize = max_length - 1;
    for (pats) |v| {
        try testing.expect(v != 0);

        const decisions: usize = msbIndex(v);
        const k: usize = decisions + 1;
        try testing.expect(k >= 1 and k <= pickup);

        const mask: u8 = v & ((@as(u8, 1) << @intCast(decisions)) - 1);
        try testing.expect(@popCount(mask) <= max_moves);

        // Leading bit is always set.
        try testing.expect((v & (@as(u8, 1) << @intCast(decisions))) != 0);
    }
}

fn assertCrushSliceValid(pickup: usize, max_length: usize, pats: []const u8) !void {
    try testing.expect(pickup >= 1 and pickup <= brd.max_pickup);
    try testing.expect(max_length >= 1 and max_length <= brd.max_pickup);

    // Structural invariants of generateCrushPatternsForConfig.
    const required_moves: usize = max_length - 1;
    for (pats) |v| {
        try testing.expect(v != 0);
        try testing.expect((v & 0b1) == 1);

        const decisions: usize = msbIndex(v);
        const k: usize = decisions + 1;
        try testing.expect(k >= max_length and k <= pickup);

        const mask: u8 = v & ((@as(u8, 1) << @intCast(decisions)) - 1);
        try testing.expect(@popCount(mask) == required_moves);
    }
}

test "PatternList initialization" {
    const list = sym.PatternList.init();
    try testing.expectEqual(@as(usize, 0), list.len);
}

test "PatternList add" {
    var list = sym.PatternList.init();

    list.add(0b10000000);
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expectEqual(@as(u8, 0b10000000), list.items[0]);

    list.add(0b11000000);
    try testing.expectEqual(@as(usize, 2), list.len);
    try testing.expectEqual(@as(u8, 0b11000000), list.items[1]);
}

test "patterns - pickup 1, length 1" {
    const pats = sym.patterns.get(1, 1);

    try testing.expectEqual(@as(usize, 1), pats.len);
    try testing.expectEqual(@as(u8, 0b00000001), pats[0]);
}

test "patterns - pickup 2, length 1" {
    const pats = sym.patterns.get(2, 1);

    try testing.expectEqual(@as(usize, 2), pats.len);
    try testing.expectEqual(@as(u8, 0b00000001), pats[0]);
    try testing.expectEqual(@as(u8, 0b00000010), pats[1]);
}

test "patterns - pickup 2, length 2" {
    const pats = sym.patterns.get(2, 2);

    const patterns_expected = [_]u8{
        0b00000001,
        0b00000010,
        0b00000011,
    };

    try testing.expectEqual(@as(usize, patterns_expected.len), pats.len);
    for (0..patterns_expected.len) |i| {
        try testing.expectEqual(patterns_expected[i], pats[i]);
    }
}

test "patterns - pickup 3, length 4" {
    const pats = sym.patterns.get(3, 4);

    const patterns_expected = [_]u8{
        0b00000001,
        0b00000010,
        0b00000011,
        0b00000100,
        0b00000101,
        0b00000110,
        0b00000111,
    };

    try testing.expectEqual(@as(usize, patterns_expected.len), pats.len);
    for (0..patterns_expected.len) |i| {
        try testing.expectEqual(patterns_expected[i], pats[i]);
    }
}

test "patterns - pickup 4, length 3" {
    const pats = sym.patterns.get(4, 3);

    const patterns_expected = [_]u8{
        0b00000001,
        0b00000010,
        0b00000011,
        0b00000100,
        0b00000101,
        0b00000110,
        0b00000111,
        0b00001000,
        0b00001001,
        0b00001010,
        0b00001011,
        0b00001100,
        0b00001101,
        0b00001110,
    };

    try testing.expectEqual(@as(usize, patterns_expected.len), pats.len);
    for (0..patterns_expected.len) |i| {
        try testing.expectEqual(patterns_expected[i], pats[i]);
    }
}

test "crush - pickup 1, length 1" {
    const pats = sym.patterns.getcrush(1, 1);

    try testing.expectEqual(@as(usize, 1), pats.len);
    try testing.expectEqual(@as(u8, 0b00000001), pats[0]);
}

test "crush - pickup 2, length 1" {
    const pats = sym.patterns.getcrush(2, 1);

    const expected = [_]u8{
        0b00000001,
    };

    try testing.expectEqual(@as(usize, expected.len), pats.len);
    for (0..expected.len) |i| try testing.expectEqual(expected[i], pats[i]);
}

test "crush - pickup 2, length 2" {
    const pats = sym.patterns.getcrush(2, 2);

    const expected = [_]u8{
        0b00000011,
    };

    try testing.expectEqual(@as(usize, expected.len), pats.len);
    for (0..expected.len) |i| try testing.expectEqual(expected[i], pats[i]);
}

test "crush - pickup 3, length 2" {
    const pats = sym.patterns.getcrush(3, 2);

    const expected = [_]u8{
        0b00000011,
        0b00000101,
    };

    try testing.expectEqual(@as(usize, expected.len), pats.len);
    for (0..expected.len) |i| try testing.expectEqual(expected[i], pats[i]);
}

test "crush - pickup 4, length 3" {
    const pats = sym.patterns.getcrush(4, 3);

    const expected = [_]u8{
        0b00000111,
        0b00001011,
        0b00001101,
    };

    try testing.expectEqual(@as(usize, expected.len), pats.len);
    for (0..expected.len) |i| try testing.expectEqual(expected[i], pats[i]);
}

test "PatternList combine appends in-order" {
    var a = sym.PatternList.init();
    var b = sym.PatternList.init();

    a.add(0b00000001);
    a.add(0b00000010);
    b.add(0b00000100);
    b.add(0b00001000);

    a.combine(&b);
    try testing.expectEqual(@as(usize, 4), a.len);
    try testing.expectEqual(@as(u8, 0b00000001), a.items[0]);
    try testing.expectEqual(@as(u8, 0b00000010), a.items[1]);
    try testing.expectEqual(@as(u8, 0b00000100), a.items[2]);
    try testing.expectEqual(@as(u8, 0b00001000), a.items[3]);
}

test "patterns - property checks across all pickup/length" {
    // Validates ordering, uniqueness, and the exact combinatorial count implied
    // by generatePatternsForConfig.
    for (1..brd.max_pickup + 1) |pickup| {
        for (1..brd.max_pickup + 1) |max_length| {
            const pats = sym.patterns.get(pickup, max_length);

            // Non-empty: k=1 always contributes value 1.
            try testing.expect(pats.len > 0);

            try assertStrictlyIncreasing(pats);
            try assertAllDistinct(pats);
            try assertPatternSliceValid(pickup, max_length, pats);

            const expected_len: u64 = expectedPatternCount(pickup, max_length);
            try testing.expectEqual(expected_len, @as(u64, @intCast(pats.len)));
        }
    }
}

test "crush - property checks across all pickup/length" {
    // Validates ordering, uniqueness, and the exact combinatorial count implied
    // by generateCrushPatternsForConfig.
    for (1..brd.max_pickup + 1) |pickup| {
        for (1..brd.max_pickup + 1) |max_length| {
            const pats = sym.patterns.getcrush(pickup, max_length);

            // If max_length > pickup, generateCrushPatternsForConfig skips all k.
            if (max_length > pickup) {
                try testing.expectEqual(@as(usize, 0), pats.len);
                continue;
            }

            try assertStrictlyIncreasing(pats);
            try assertAllDistinct(pats);
            try assertCrushSliceValid(pickup, max_length, pats);

            const expected_len: u64 = expectedCrushCount(pickup, max_length);
            try testing.expectEqual(expected_len, @as(u64, @intCast(pats.len)));
        }
    }
}

test "combined_patterns is previous-length patterns + crush patterns" {
    // Patterns.init builds combined_patterns[pickup][len] as:
    //   (if len>1) patterns[pickup][len-1] appended with crush_patterns[pickup][len].
    for (1..brd.max_pickup + 1) |pickup| {
        for (1..brd.max_pickup + 1) |max_length| {
            const prev = if (max_length > 1) sym.patterns.get(pickup, max_length - 1) else &[_]u8{};
            const crush = sym.patterns.getcrush(pickup, max_length);

            const combined_list = &sym.patterns.combined_patterns[pickup - 1][max_length - 1];
            const combined = combined_list.items[0..combined_list.len];

            try testing.expectEqual(prev.len + crush.len, combined.len);

            // Verify concatenation order.
            for (0..prev.len) |i| try testing.expectEqual(prev[i], combined[i]);
            for (0..crush.len) |i| try testing.expectEqual(crush[i], combined[prev.len + i]);
        }
    }
}

