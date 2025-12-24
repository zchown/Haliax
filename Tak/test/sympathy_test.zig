const std = @import("std");
const sym = @import("sympathy");
const brd = @import("board");
const testing = std.testing;

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

    // for (0..pats.len) |i| {
    //     std.debug.print("Pattern: {b}\n", .{pats[i]});
    // }

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

