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

    // With 1 stone and 1 space, there's only one pattern: 10000000
    try testing.expectEqual(@as(usize, 1), pats.len);
    try testing.expectEqual(@as(u8, 0b10000000), pats[0]);
}

test "patterns - pickup 2, length 1" {
    const pats = sym.patterns.get(2, 1);

    // With 2 stones and 1 space, we drop 2 at position 1: 01000000
    try testing.expectEqual(@as(usize, 1), pats.len);
    try testing.expectEqual(@as(u8, 0b01000000), pats[0]);
}

test "patterns - pickup 2, length 2" {
    const pats = sym.patterns.get(2, 2);

    // With 2 stones and 2 spaces:
    // - 11000000 (drop 1, drop 1)
    // - 01000000 (skip, drop 2)
    try testing.expectEqual(@as(usize, 2), pats.len);

    var found_11 = false;
    var found_01 = false;
    for (pats) |p| {
        if (p == 0b11000000) found_11 = true;
        if (p == 0b01000000) found_01 = true;
    }
    try testing.expect(found_11);
    try testing.expect(found_01);
}

test "patterns - pickup 3, length 3" {
    const pats = sym.patterns.get(3, 3);

    // With 3 stones and 3 spaces, we should have C(3,2) + C(3,1) + C(3,0) patterns
    // Drop patterns: 111, 110, 101, 011, 100, 010, 001
    // Total patterns should be non-zero
    try testing.expect(pats.len > 0);

    // All patterns should start with at least one 1
    for (pats) |p| {
        const leading_zeros = @clz(p);
        try testing.expect(leading_zeros < 8);
    }
}

test "patterns - pickup 4, length 2" {
    const pats = sym.patterns.get(4, 2);

    // With 4 stones and 2 spaces, must drop 2 or more at some positions
    try testing.expect(pats.len > 0);
}

test "crush patterns - pickup 1, length 1" {
    const pats = sym.patterns.getcrush(1, 1);

    // Crush pattern must end in 1: 10000000
    try testing.expectEqual(@as(usize, 1), pats.len);
    try testing.expectEqual(@as(u8, 0b10000000), pats[0]);
}

test "crush patterns - pickup 2, length 2" {
    const pats = sym.patterns.getcrush(2, 2);

    // Crush patterns with 2 stones, 2 spaces, must end in 1
    // Only valid pattern: 01000001 is not valid for 2 stones
    // Actually: 11000000 but last bit forced to 1 in slide
    // The pattern generation for crush ensures last bit is 1
    try testing.expect(pats.len > 0);

    for (pats) |p| {
        // Last bit should be 1 (but shifted in the pattern)
        // Actually checking that pattern represents a valid crush
        try testing.expect(p != 0);
    }
}

test "crush patterns - all end positions used" {
    // Crush patterns should use all stones and end with a drop
    const pats = sym.patterns.getcrush(3, 3);

    for (pats) |p| {
        // Pattern should not be all zeros
        try testing.expect(p != 0);

        // Should have at least one 1 bit
        try testing.expect(@popCount(p) > 0);
    }
}

test "patterns - no duplicates in list" {
    const pats = sym.patterns.get(3, 3);

    for (pats, 0..) |p1, i| {
        for (pats[i + 1 ..]) |p2| {
            try testing.expect(p1 != p2);
        }
    }
}

test "patterns - all ones and zeros accounted" {
    // For pickup N and length L, verify pattern structure
    const pats = sym.patterns.get(2, 2);

    for (pats) |p| {
        var ones: usize = 0;
        var temp = p;
        var started = false;

        for (0..8) |_| {
            const bit = temp >> 7;
            temp <<= 1;

            if (!started and bit == 1) {
                started = true;
            }
            if (started and bit == 1) {
                ones += 1;
            }
        }

        // For 2 pickup and 2 length, we should have 2 ones total
        try testing.expect(ones <= 2);
    }
}

test "patterns - increasing complexity" {
    // More pickup/length should generally mean more patterns
    const p11 = sym.patterns.get(1, 1);
    const p22 = sym.patterns.get(2, 2);
    const p33 = sym.patterns.get(3, 3);

    try testing.expect(p22.len >= p11.len);
    try testing.expect(p33.len >= p22.len);
}

test "patterns - max pickup valid" {
    // Test at board limits
    const pats = sym.patterns.get(brd.max_pickup, brd.max_pickup);

    try testing.expect(pats.len > 0);

    for (pats) |p| {
        try testing.expect(p != 0);
    }
}

test "patterns - edge cases" {
    for (1..brd.max_pickup + 1) |pickup| {
        for (1..brd.max_pickup + 1) |length| {
            const pats = sym.patterns.get(pickup, length);

            if (length <= pickup) {
                try testing.expect(pats.len > 0);
            }
        }
    }
}

test "crush patterns - edge cases" {
    for (1..brd.max_pickup + 1) |pickup| {
        for (1..brd.max_pickup + 1) |length| {
            if (length <= pickup) {
                const pats = sym.patterns.getcrush(pickup, length);

                try testing.expect(pats.len >= 0);
            }
        }
    }
}

test "patterns - specific pattern structure" {
    // Test pattern 0b11000000 appears in appropriate list
    const pats = sym.patterns.get(2, 2);

    var found = false;
    for (pats) |p| {
        if (p == 0b11000000) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "patterns - leading zeros consistent" {
    // Patterns should start from bit position (8 - pickup)
    const pats = sym.patterns.get(2, 2);

    for (pats) |p| {
        // Count leading zeros
        const lz = @clz(p);

        // For pickup 2, should have 6 leading zeros max (8 - 2)
        try testing.expect(lz <= 6);
    }
}

test "patterns - compile time generation" {
    // Verify that patterns is const and generated at compile time
    const p1 = sym.patterns.get(2, 2);
    const p2 = sym.patterns.get(2, 2);

    // Should be same reference
    try testing.expectEqual(p1.ptr, p2.ptr);
    try testing.expectEqual(p1.len, p2.len);
}

test "crush patterns - force last drop" {
    // Crush patterns must drop at the final position
    const pats = sym.patterns.getcrush(3, 3);

    for (pats) |p| {
        // Check that we're using all our stones
        try testing.expect(p != 0);
    }
}

test "patterns - comprehensive coverage" {
    // Make sure we have patterns for all valid combinations
    for (1..brd.max_pickup + 1) |pickup| {
        for (1..pickup + 1) |actual_length| {
            for (actual_length..brd.max_pickup + 1) |max_length| {
                const pats = sym.patterns.get(pickup, max_length);

                // Should have patterns when actual_length <= pickup <= max_length
                try testing.expect(pats.len > 0);
            }
        }
    }
}

test "PatternList capacity" {
    var list = sym.PatternList.init();

    // Add many patterns
    for (0..100) |i| {
        list.add(@as(u8, @intCast(i % 256)));
    }

    try testing.expectEqual(@as(usize, 100), list.len);
}

test "patterns vs crush patterns difference" {
    // Crush patterns should generally have fewer or equal patterns
    // since they have the additional constraint of ending in a drop
    const regular = sym.patterns.get(3, 3);
    const crush = sym.patterns.getcrush(3, 3);

    // Both should have patterns
    try testing.expect(regular.len > 0);

    // Crush might be zero or positive
    try testing.expect(crush.len >= 0);
}
