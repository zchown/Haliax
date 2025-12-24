const std = @import("std");
const ptn = @import("../src/ptn.zig");
const brd = @import("../src/board.zig");
const testing = std.testing;

test "PTN init and deinit" {
    var p = try ptn.PTN.init(testing.allocator);
    defer p.deinit();

    try testing.expectEqual(@as(usize, 0), p.moves.items.len);
    try testing.expect(p.site == null);
    try testing.expect(p.player1 == null);
}

test "parseMove - simple flat placement" {
    const move = try ptn.parseMove("a1", .White);

    try testing.expectEqual(brd.getPos(0, 0), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.StoneType.Flat)), move.flag);
    try testing.expectEqual(@as(u8, 0), move.pattern);
}

test "parseMove - standing stone" {
    const move = try ptn.parseMove("Sa3", .White);

    try testing.expectEqual(brd.getPos(0, 2), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.StoneType.Standing)), move.flag);
    try testing.expectEqual(@as(u8, 0), move.pattern);
}

test "parseMove - capstone" {
    const move = try ptn.parseMove("Cf6", .White);

    try testing.expectEqual(brd.getPos(5, 5), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.StoneType.Capstone)), move.flag);
    try testing.expectEqual(@as(u8, 0), move.pattern);
}

test "parseMove - simple slide north" {
    const move = try ptn.parseMove("a1+", .White);

    try testing.expectEqual(brd.getPos(0, 0), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.Direction.North)), move.flag);
    try testing.expect(move.pattern != 0);
}

test "parseMove - simple slide south" {
    const move = try ptn.parseMove("b2-", .White);

    try testing.expectEqual(brd.getPos(1, 1), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.Direction.South)), move.flag);
}

test "parseMove - simple slide east" {
    const move = try ptn.parseMove("c3>", .White);

    try testing.expectEqual(brd.getPos(2, 2), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.Direction.East)), move.flag);
}

test "parseMove - simple slide west" {
    const move = try ptn.parseMove("d4<", .White);

    try testing.expectEqual(brd.getPos(3, 3), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.Direction.West)), move.flag);
}

test "parseMove - slide with count" {
    const move = try ptn.parseMove("3a1+", .White);

    try testing.expectEqual(brd.getPos(0, 0), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.Direction.North)), move.flag);
}

test "parseMove - slide with drops" {
    const move = try ptn.parseMove("3a1+12", .White);

    try testing.expectEqual(brd.getPos(0, 0), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.Direction.North)), move.flag);
    try testing.expect(move.pattern != 0);
}

test "parseMove - with crush indicator" {
    const move = try ptn.parseMove("a1+*", .White);

    try testing.expectEqual(brd.getPos(0, 0), move.position);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.Direction.North)), move.flag);
}

test "directionToChar conversions" {
    try testing.expectEqual(@as(u8, '+'), ptn.directionToChar(.North));
    try testing.expectEqual(@as(u8, '-'), ptn.directionToChar(.South));
    try testing.expectEqual(@as(u8, '>'), ptn.directionToChar(.East));
    try testing.expectEqual(@as(u8, '<'), ptn.directionToChar(.West));
}

test "moveToString - flat placement" {
    var allocator = testing.allocator;
    const move = brd.Move.createPlaceMove(brd.getPos(2, 3), .Flat);
    const str = try ptn.moveToString(&allocator, move, .White);
    defer allocator.free(str);

    try testing.expectEqualStrings("c4", str);
}

test "moveToString - standing stone" {
    var allocator = testing.allocator;
    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Standing);
    const str = try ptn.moveToString(&allocator, move, .White);
    defer allocator.free(str);

    try testing.expectEqualStrings("Sa1", str);
}

test "moveToString - capstone" {
    var allocator = testing.allocator;
    const move = brd.Move.createPlaceMove(brd.getPos(5, 5), .Capstone);
    const str = try ptn.moveToString(&allocator, move, .White);
    defer allocator.free(str);

    try testing.expectEqualStrings("Cf6", str);
}

test "moveToString - simple slide" {
    var allocator = testing.allocator;
    const move = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 1);
    const str = try ptn.moveToString(&allocator, move, .White);
    defer allocator.free(str);

    try testing.expect(str.len >= 3);
    try testing.expectEqual(@as(u8, 'a'), str[0]);
    try testing.expectEqual(@as(u8, '1'), str[1]);
    try testing.expectEqual(@as(u8, '+'), str[2]);
}

test "parsePTN - empty content" {
    var p = try ptn.parsePTN(testing.allocator, "");
    defer p.deinit();

    try testing.expectEqual(@as(usize, 0), p.moves.items.len);
}

test "parsePTN - with header tags" {
    const ptn_text =
        \\[Site: PlayTak.com]
        \\[Player1: Alice]
        \\[Player2: Bob]
        \\[Size: 6]
        \\
        \\1. a1 f6
        ;

    var p = try ptn.parsePTN(testing.allocator, ptn_text);
    defer p.deinit();

    try testing.expect(p.site != null);
    try testing.expect(p.player1 != null);
    try testing.expect(p.player2 != null);
    try testing.expectEqual(@as(usize, 6), p.size);
    try testing.expectEqual(@as(usize, 2), p.moves.items.len);
}

test "parsePTN - with multiple moves" {
    const ptn_text =
        \\[Size: 6]
        \\
        \\1. a1 f6
        \\2. b2 e5
        \\3. c3 d4
        ;

    var p = try ptn.parsePTN(testing.allocator, ptn_text);
    defer p.deinit();

    try testing.expectEqual(@as(usize, 6), p.moves.items.len);
}

test "parsePTN - with game result notation" {
    const ptn_text =
        \\[Size: 6]
        \\
        \\1. a1 f6
        \\2. b2 R-0
        ;

    var p = try ptn.parsePTN(testing.allocator, ptn_text);
    defer p.deinit();

    try testing.expectEqual(@as(usize, 3), p.moves.items.len);
}

test "parsePTN - with blank lines" {
    const ptn_text =
        \\[Size: 6]
        \\
        \\
        \\1. a1 f6
        \\
        \\2. b2 e5
        \\
        ;

    var p = try ptn.parsePTN(testing.allocator, ptn_text);
    defer p.deinit();

    try testing.expectEqual(@as(usize, 4), p.moves.items.len);
}

test "parsePTN - with various stone types" {
    const ptn_text =
        \\1. a1 f6
        \\2. Sb2 Ce5
        \\3. c3 d4
        ;

    var p = try ptn.parsePTN(testing.allocator, ptn_text);
    defer p.deinit();

    try testing.expectEqual(@as(usize, 6), p.moves.items.len);

    try testing.expectEqual(@as(u2, @intFromEnum(brd.StoneType.Standing)), p.moves.items[2].flag);
    try testing.expectEqual(@as(u2, @intFromEnum(brd.StoneType.Capstone)), p.moves.items[3].flag);
}

test "parsePTN - with slide moves" {
    const ptn_text =
        \\1. a1 f6
        \\2. b2 e5
        \\3. a1+ 3f6-12
        ;

    var p = try ptn.parsePTN(testing.allocator, ptn_text);
    defer p.deinit();

    try testing.expectEqual(@as(usize, 6), p.moves.items.len);

    try testing.expect(p.moves.items[4].pattern != 0);
    try testing.expect(p.moves.items[5].pattern != 0);
}

test "parsePTN - opening moves color swap" {
    const ptn_text =
        \\1. a1 f6
        \\2. b2 e5
        ;

    var p = try ptn.parsePTN(testing.allocator, ptn_text);
    defer p.deinit();

    try testing.expectEqual(@as(usize, 4), p.moves.items.len);
}

test "parseMove - all positions" {
    const positions = [_][]const u8{
        "a1", "a2", "a3", "a4", "a5", "a6",
        "b1", "b2", "b3", "b4", "b5", "b6",
        "c1", "c2", "c3", "c4", "c5", "c6",
        "d1", "d2", "d3", "d4", "d5", "d6",
        "e1", "e2", "e3", "e4", "e5", "e6",
        "f1", "f2", "f3", "f4", "f5", "f6",
    };

    for (positions, 0..) |pos_str, i| {
        const move = try ptn.parseMove(pos_str, .White);
        const expected_x = i % 6;
        const expected_y = i / 6;

        try testing.expectEqual(brd.getPos(expected_x, expected_y), move.position);
    }
}

test "parseMove - invalid position" {
    try testing.expectError(ptn.PTNParseError.PositionError, ptn.parseMove("g1", .White));
    try testing.expectError(ptn.PTNParseError.PositionError, ptn.parseMove("a7", .White));
    try testing.expectError(ptn.PTNParseError.PositionError, ptn.parseMove("z9", .White));
}

test "parseMove - invalid format" {
    try testing.expectError(ptn.PTNParseError.PositionError, ptn.parseMove("1", .White));
    try testing.expectError(ptn.PTNParseError.PositionError, ptn.parseMove("a", .White));
}

test "round trip - place moves" {
    var allocator = testing.allocator;

    const test_cases = [_][]const u8{
        "a1",
        "Sa3",
        "Cf6",
        "b4",
        "Sc2",
    };

    for (test_cases) |original| {
        const move = try ptn.parseMove(original, .White);
        const converted = try ptn.moveToString(&allocator, move, .White);
        defer allocator.free(converted);

        try testing.expectEqualStrings(original, converted);
    }
}

test "round trip - slide moves" {
    var allocator = testing.allocator;

    const test_cases = [_][]const u8{
        "a1+",
        "b2-",
        "c3>",
        "d4<",
    };

    for (test_cases) |original| {
        const move = try ptn.parseMove(original, .White);
        const converted = try ptn.moveToString(&allocator, move, .White);
        defer allocator.free(converted);

        try testing.expectEqualStrings(original, converted);
    }
}
