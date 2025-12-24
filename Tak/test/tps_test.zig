const std = @import("std");
const brd = @import("board");
const tps = @import("tps");
const testing = std.testing;

test "parseTPS - empty board" {
    const board = try tps.parseTPS("[TPS x6/x6/x6/x6/x6/x6 1 10]");

    try testing.expectEqual(brd.Color.White, board.to_move);
    try testing.expectEqual(@as(usize, 9), board.half_move_count);
    try testing.expectEqual(brd.board_mask, board.empty_squares);

    for (0..brd.num_squares) |i| {
        try testing.expectEqual(@as(usize, 0), board.squares[i].len);
    }
}

test "parseTPS - with single piece" {
    const board = try tps.parseTPS("[TPS x3,1,2,x/x6/x6/x6/x6/x6 1 5]");

    const pos = brd.getPos(3, 5);
    try testing.expectEqual(@as(usize, 1), board.squares[pos].len);
    try testing.expectEqual(brd.Color.White, board.squares[pos].top().?.color);
    try testing.expectEqual(brd.StoneType.Flat, board.squares[pos].top().?.stone_type);

    const pos2 = brd.getPos(4, 5);
    try testing.expectEqual(@as(usize, 1), board.squares[pos2].len);
    try testing.expectEqual(brd.Color.Black, board.squares[pos2].top().?.color);
}

test "parseTPS - with standing stone" {
    const board = try tps.parseTPS("[TPS x5,1S/x6/x6/x6/x6/x6 1 1]");

    const pos = brd.getPos(5, 5);
    try testing.expectEqual(brd.StoneType.Standing, board.squares[pos].top().?.stone_type);
    try testing.expect(brd.getBit(board.standing_stones, pos));
}

test "parseTPS - with capstone" {
    const board = try tps.parseTPS("[TPS x5,2C/x6/x6/x6/x6/x6 1 1]");

    const pos = brd.getPos(5, 5);
    try testing.expectEqual(brd.StoneType.Capstone, board.squares[pos].top().?.stone_type);
    try testing.expect(brd.getBit(board.capstones, pos));
}

test "parseTPS - with stacked pieces" {
    const board = try tps.parseTPS("[TPS x5,12/x6/x6/x6/x6/x6 1 1]");

    const pos = brd.getPos(5, 5);
    try testing.expectEqual(@as(usize, 2), board.squares[pos].len);
    try testing.expectEqual(brd.Color.White, board.squares[pos].stack[0].?.color);
    try testing.expectEqual(brd.Color.Black, board.squares[pos].stack[1].?.color);
}

test "parseTPS - complex stack" {
    const board = try tps.parseTPS("[TPS x,212121,x4/x6/x6/x6/x6/x6 1 1]");

    const pos = brd.getPos(1, 5);
    try testing.expectEqual(@as(usize, 6), board.squares[pos].len);

    try testing.expectEqual(brd.Color.Black, board.squares[pos].stack[0].?.color);
    try testing.expectEqual(brd.Color.White, board.squares[pos].stack[1].?.color);
    try testing.expectEqual(brd.Color.Black, board.squares[pos].stack[2].?.color);
}

test "parseTPS - turn indicator" {
    const board1 = try tps.parseTPS("[TPS x6/x6/x6/x6/x6/x6 1 1]");
    try testing.expectEqual(brd.Color.White, board1.to_move);

    const board2 = try tps.parseTPS("[TPS x6/x6/x6/x6/x6/x6 2 1]");
    try testing.expectEqual(brd.Color.Black, board2.to_move);
}

test "parseTPS - move number" {
    const board1 = try tps.parseTPS("[TPS x6/x6/x6/x6/x6/x6 1 1]");
    try testing.expectEqual(@as(usize, 0), board1.half_move_count);

    const board2 = try tps.parseTPS("[TPS x6/x6/x6/x6/x6/x6 1 42]");
    try testing.expectEqual(@as(usize, 41), board2.half_move_count);
}

test "parseTPS - without TPS prefix" {
    const board = try tps.parseTPS("x6/x6/x6/x6/x6/x6 1 10");

    try testing.expectEqual(brd.Color.White, board.to_move);
    try testing.expectEqual(@as(usize, 9), board.half_move_count);
}

test "parseTPS - full board" {
    const board = try tps.parseTPS("[TPS 1,1,1,1,1,2/1,1,1,1,2,1/1,x2,2,1,1/x2,2,1,1,1/x,2,1,1,1,1/2,x5 2 20]");

    try testing.expectEqual(brd.Color.Black, board.to_move);
    try testing.expectEqual(@as(usize, 19), board.half_move_count);

    const pos1 = brd.getPos(0, 5);
    try testing.expectEqual(brd.Color.White, board.squares[pos1].top().?.color);

    const pos2 = brd.getPos(5, 5);
    try testing.expectEqual(brd.Color.Black, board.squares[pos2].top().?.color);
}

test "parseTPS - empty squares with count" {
    const board = try tps.parseTPS("[TPS x3,1,x2/x6/x6/x6/x6/x6 1 1]");

    for (0..3) |x| {
        try testing.expectEqual(@as(usize, 0), board.squares[brd.getPos(x, 5)].len);
    }

    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(3, 5)].len);

    for (4..6) |x| {
        try testing.expectEqual(@as(usize, 0), board.squares[brd.getPos(x, 5)].len);
    }
}

test "boardToTPS - empty board" {
    var board = brd.Board.init();
    const tps_str = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str);

    try testing.expectEqualStrings("[TPS x6/x6/x6/x6/x6/x6 1 1]", tps_str);
}

test "boardToTPS - with single piece" {
    var board = brd.Board.init();
    board.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });

    const tps_str = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str);

    try testing.expectEqualStrings("[TPS x6/x6/x6/x6/x6/1,x5 1 1]", tps_str);
}

test "boardToTPS - with standing stone" {
    var board = brd.Board.init();
    board.squares[brd.getPos(5, 5)].push(brd.Piece{
        .stone_type = .Standing,
        .color = .White,
    });

    const tps_str = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str);

    try testing.expectEqualStrings("[TPS x5,1S/x6/x6/x6/x6/x6 1 1]", tps_str);
}

test "boardToTPS - with capstone" {
    var board = brd.Board.init();
    board.squares[brd.getPos(2, 3)].push(brd.Piece{
        .stone_type = .Capstone,
        .color = .Black,
    });

    const tps_str = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str);

    try testing.expectEqualStrings("[TPS x6/x6/x2,2C,x3/x6/x6/x6 1 1]", tps_str);
}

test "boardToTPS - with stack" {
    var board = brd.Board.init();
    board.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    board.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });

    const tps_str = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str);

    try testing.expectEqualStrings("[TPS x6/x6/x6/x6/x6/12,x5 1 1]", tps_str);
}

test "boardToTPS - black to move" {
    var board = brd.Board.init();
    board.to_move = .Black;

    const tps_str = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str);

    try testing.expectEqualStrings("[TPS x6/x6/x6/x6/x6/x6 2 1]", tps_str);
}

test "boardToTPS - with move count" {
    var board = brd.Board.init();
    board.half_move_count = 15;

    const tps_str = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str);

    try testing.expectEqualStrings("[TPS x6/x6/x6/x6/x6/x6 1 16]", tps_str);
}

test "round trip - empty board" {
    const original = "[TPS x6/x6/x6/x6/x6/x6 1 10]";
    var board = try tps.parseTPS(original);
    const result = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(original, result);
}

test "round trip - with pieces" {
    const original = "[TPS x5,1/x6/x6/x6/x6/x6 1 5]";
    var board = try tps.parseTPS(original);
    const result = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(original, result);
}

test "round trip - complex position" {
    const original = "[TPS 1,x3,2C,x/1,x2,2,x2/1,1,1,2,2S,x/1,x,1,x3/2,x,1,x3/x2,2,x3 2 1]";
    var board = try tps.parseTPS(original);
    const result = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(original, result);
}

test "round trip - full board" {
    const original = "[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]";
    var board = try tps.parseTPS(original);
    const result = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(original, result);
}

test "parseTPS - updates piece counts" {
    const board = try tps.parseTPS("[TPS x5,1/x6/x6/x6/x6/x6 1 5]");

    try testing.expectEqual(@as(usize, brd.stone_count - 1), board.white_stones_remaining);
    try testing.expectEqual(@as(usize, brd.stone_count), board.black_stones_remaining);
}

test "parseTPS - updates control bitboards" {
    const board = try tps.parseTPS("[TPS x5,1/x6/x6/x6/x6/x6 1 5]");

    const pos = brd.getPos(5, 5);
    try testing.expect(brd.getBit(board.white_control, pos));
    try testing.expect(!brd.getBit(board.black_control, pos));
}

test "parseTPS - invalid row count" {
    try testing.expectError(tps.TPSError.InvalidRowCount, tps.parseTPS("[TPS x6/x6/x6/x6/x6 1 10]"));
}

test "parseTPS - invalid column count" {
    try testing.expectError(tps.TPSError.InvalidColumnCount, tps.parseTPS("[TPS x5/x6/x6/x6/x6/x6 1 10]"));
}

test "parseTPS - vertical road position" {
    const board = try tps.parseTPS("[TPS 2,x5/2,x5/2,x5/2,x5/2,x5/2,x5 2 2]");

    for (0..brd.board_size) |y| {
        const pos = brd.getPos(0, y);
        try testing.expectEqual(brd.Color.Black, board.squares[pos].top().?.color);
    }
}

test "parseTPS - horizontal road position" {
    const board = try tps.parseTPS("[TPS 1,1,1,1,1,1/x6/x6/x6/x6/x6 2 2]");

    for (0..brd.board_size) |x| {
        const pos = brd.getPos(x, 5);
        try testing.expectEqual(brd.Color.White, board.squares[pos].top().?.color);
    }
}
