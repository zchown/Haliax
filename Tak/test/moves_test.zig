const std = @import("std");
const brd = @import("board");
const moves = @import("moves");
const magic = @import("magics");
const tps = @import("tps");
const ptn = @import("ptn");
const testing = std.testing;

test "MoveList initialization" {
    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 10);
    defer move_list.deinit();

    try testing.expectEqual(@as(usize, 0), move_list.count);
    try testing.expectEqual(@as(usize, 10), move_list.capacity);
}

test "MoveList append" {
    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 2);
    defer move_list.deinit();

    const move1 = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    try move_list.append(move1);
    try testing.expectEqual(@as(usize, 1), move_list.count);

    const move2 = brd.Move.createPlaceMove(brd.getPos(1, 1), .Standing);
    try move_list.append(move2);
    try testing.expectEqual(@as(usize, 2), move_list.count);

    const move3 = brd.Move.createPlaceMove(brd.getPos(2, 2), .Capstone);
    try move_list.append(move3);
    try testing.expectEqual(@as(usize, 3), move_list.count);
    try testing.expect(move_list.capacity >= 3);
}

test "MoveList clear" {
    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 10);
    defer move_list.deinit();

    const move1 = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    try move_list.append(move1);

    move_list.clear();
    try testing.expectEqual(@as(usize, 0), move_list.count);
}

test "checkMove - valid place moves" {
    const b = brd.Board.init();

    const flat_move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    try moves.checkMove(b, flat_move);

    const standing_move = brd.Move.createPlaceMove(brd.getPos(1, 1), .Standing);
    try moves.checkMove(b, standing_move);

    const cap_move = brd.Move.createPlaceMove(brd.getPos(2, 2), .Capstone);
    try moves.checkMove(b, cap_move);
}

test "checkMove - invalid position" {
    var board = brd.Board.init();

    board.squares[brd.getPos(0, 0)].pushPiece(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    board.empty_squares = board.empty_squares & ~brd.getPositionBB(brd.getPos(0, 0));

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    try testing.expectError(moves.MoveError.InvalidPosition, moves.checkMove(board, move));
}

test "checkMove - no stones remaining" {
    var board = brd.Board.init();
    board.white_stones_remaining = 0;

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    try testing.expectError(moves.MoveError.InvalidStone, moves.checkMove(board, move));
}

test "checkMove - no capstones remaining" {
    var board = brd.Board.init();
    board.white_capstones_remaining = 0;

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Capstone);
    try testing.expectError(moves.MoveError.InvalidStone, moves.checkMove(board, move));
}

test "makeMove - place flat stone" {
    var board = brd.Board.init();
    const initial_hash = board.zobrist_hash;

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    moves.makeMove(&board, move);

    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 0)].len);
    try testing.expectEqual(brd.StoneType.Flat, board.squares[brd.getPos(0, 0)].top().?.stone_type);
    try testing.expectEqual(@as(usize, brd.stone_count - 1), board.black_stones_remaining);
    try testing.expectEqual(brd.Color.Black, board.to_move);
    try testing.expectEqual(@as(usize, 1), board.half_move_count);
    try testing.expect(initial_hash != board.zobrist_hash);
}

test "makeMove - place capstone" {
    var board = brd.Board.init();

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Capstone);
    moves.makeMove(&board, move);

    try testing.expectEqual(brd.StoneType.Capstone, board.squares[brd.getPos(0, 0)].top().?.stone_type);
    try testing.expectEqual(@as(usize, brd.capstone_count - 1), board.black_capstones_remaining);
    try testing.expect(brd.getBit(board.capstones, brd.getPos(0, 0)));
}

test "makeMove - place standing stone" {
    var board = brd.Board.init();

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Standing);
    moves.makeMove(&board, move);

    try testing.expectEqual(brd.StoneType.Standing, board.squares[brd.getPos(0, 0)].top().?.stone_type);
    try testing.expect(brd.getBit(board.standing_stones, brd.getPos(0, 0)));
}

test "makeMove - first two moves swap colors" {
    var board = brd.Board.init();

    const move1 = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    moves.makeMove(&board, move1);
    try testing.expectEqual(brd.Color.Black, board.squares[brd.getPos(0, 0)].top().?.color);

    const move2 = brd.Move.createPlaceMove(brd.getPos(1, 1), .Flat);
    moves.makeMove(&board, move2);
    try testing.expectEqual(brd.Color.White, board.squares[brd.getPos(1, 1)].top().?.color);

    const move3 = brd.Move.createPlaceMove(brd.getPos(2, 2), .Flat);
    moves.makeMove(&board, move3);
    try testing.expectEqual(brd.Color.White, board.squares[brd.getPos(2, 2)].top().?.color);
}

test "makeMove - simple slide" {
    var board = brd.Board.init();
    board.half_move_count = 2;

    board.squares[brd.getPos(0, 0)].pushPiece(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    brd.setBit(&board.white_control, brd.getPos(0, 0));

    const move = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 0b00000001);
    moves.makeMove(&board, move);

    try testing.expectEqual(@as(usize, 0), board.squares[brd.getPos(0, 0)].len);
    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 1)].len);
}

test "makeMove - slide with crush" {
    var board = brd.Board.init();
    board.half_move_count = 2;

    board.squares[brd.getPos(0, 0)].pushPiece(brd.Piece{
        .stone_type = .Capstone,
        .color = .White,
    });
    brd.setBit(&board.white_control, brd.getPos(0, 0));

    board.squares[brd.getPos(0, 1)].pushPiece(brd.Piece{
        .stone_type = .Standing,
        .color = .Black,
    });
    brd.setBit(&board.black_control, brd.getPos(0, 1));
    brd.setBit(&board.standing_stones, brd.getPos(0, 1));

    const move = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 0b00000001);
    moves.makeMove(&board, move);

    // for (0..board.crushMoves.len) |i| {
    //     std.debug.print("Crush move {}: {}\n", .{i, board.crushMoves[i]});
    // }

    try testing.expectEqual(brd.StoneType.Flat, board.squares[brd.getPos(0, 1)].stack[0].?.stone_type);
    try testing.expectEqual(brd.Crush.Crush, board.crushMoves[2 % brd.crush_map_size]);
}

test "undoMove - place move" {
    var board = brd.Board.init();

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    moves.makeMove(&board, move);

    moves.undoMove(&board, move);

    try testing.expectEqual(@as(usize, 0), board.squares[brd.getPos(0, 0)].len);
    try testing.expectEqual(brd.Color.White, board.to_move);
    try testing.expectEqual(@as(usize, 0), board.half_move_count);
    try testing.expectEqual(@as(usize, brd.stone_count), board.white_stones_remaining);
    try testing.expectEqual(@as(usize, brd.stone_count), board.black_stones_remaining);
}

test "undoMove - slide move" {
    var board = brd.Board.init();
    board.half_move_count = 2;

    board.squares[brd.getPos(0, 0)].pushPiece(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    brd.setBit(&board.white_control, brd.getPos(0, 0));

    const move = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 0b00000001);
    moves.makeMove(&board, move);

    moves.undoMove(&board, move);

    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 0)].len);
    try testing.expectEqual(@as(usize, 0), board.squares[brd.getPos(0, 1)].len);
}

test "generateMoves - opening moves" {
    var board = brd.Board.init();
    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 100);
    defer move_list.deinit();

    try moves.generateMoves(&board, &move_list);

    try testing.expectEqual(@as(usize, brd.num_squares), move_list.count);
}

test "generateMoves - after opening" {
    var board = brd.Board.init();
    board.half_move_count = 2;

    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 200);
    defer move_list.deinit();

    try moves.generateMoves(&board, &move_list);

    try testing.expectEqual(@as(usize, brd.num_squares * 3), move_list.count);
}

test "generateMoves - with pieces on board" {
    var board = brd.Board.init();
    board.half_move_count = 2;

    board.squares[brd.getPos(2, 2)].pushPiece(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    brd.setBit(&board.white_control, brd.getPos(2, 2));
    brd.clearBit(&board.empty_squares, brd.getPos(2, 2));

    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 500);
    defer move_list.deinit();

    try moves.generateMoves(&board, &move_list);

    try testing.expect(move_list.count > brd.num_squares * 3);
}

test "checkUndoMove - valid undo" {
    var board = brd.Board.init();

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    moves.makeMove(&board, move);

    try moves.checkUndoMove(board, move);
}

test "checkUndoMove - invalid stack height" {
    var board = brd.Board.init();

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    moves.makeMove(&board, move);

    board.squares[brd.getPos(0, 0)].pushPiece(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });

    try testing.expectError(moves.MoveError.InvalidPosition, moves.checkUndoMove(board, move));
}

test "makeMoveWithCheck - valid move" {
    var board = brd.Board.init();

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    try moves.makeMoveWithCheck(&board, move);

    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 0)].len);
}

test "makeMoveWithCheck - invalid move" {
    var board = brd.Board.init();
    board.white_stones_remaining = 0;

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    try testing.expectError(moves.MoveError.InvalidStone, moves.makeMoveWithCheck(&board, move));
}

test "undoMoveWithCheck - valid undo" {
    var board = brd.Board.init();

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    moves.makeMove(&board, move);

    try moves.undoMoveWithCheck(&board, move);
    try testing.expectEqual(@as(usize, 0), board.squares[brd.getPos(0, 0)].len);
}

test "slide move with multiple drops" {
    var board = brd.Board.init();
    board.half_move_count = 2;

    for (0..3) |_| {
        board.squares[brd.getPos(0, 0)].pushPiece(brd.Piece{
            .stone_type = .Flat,
            .color = .White,
        });
    }
    brd.setBit(&board.white_control, brd.getPos(0, 0));

    const move = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 0b00000011);
    moves.makeMove(&board, move);

    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 0)].len);
    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 1)].len);
    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 2)].len);
}

test "slide move with multiple drops and undo" {
    var board = brd.Board.init();
    board.half_move_count = 2;

    for (0..3) |i| {
        board.squares[brd.getPos(0, 0)].pushPiece(brd.Piece{
            .stone_type = .Flat,
            .color = @as(brd.Color, @enumFromInt(i % 2)),
        });
    }
    brd.setBit(&board.white_control, brd.getPos(0, 0));

    const tps_str_before = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str_before);
    // std.debug.print(" tps \n", .{});
    // std.debug.print("TPS before move: {s}\n", .{tps_str_before});

    const move = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 0b00000011);
    moves.makeMove(&board, move);

    const tps_str_after = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str_after);
    // std.debug.print("TPS after move: {s}\n", .{tps_str_after});

    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 0)].len);
    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 1)].len);
    try testing.expectEqual(brd.Color.White, board.squares[brd.getPos(0, 2)].top().?.color);
    try testing.expectEqual(@as(usize, 1), board.squares[brd.getPos(0, 2)].len);
    try testing.expectEqual(brd.Color.Black, board.squares[brd.getPos(0, 1)].top().?.color);

    moves.undoMove(&board, move);

    // print tps
    const tps_str = try tps.boardToTPS(testing.allocator, &board);
    defer testing.allocator.free(tps_str);
    // std.debug.print("TPS after undo: {s}\n", .{tps_str});

    try testing.expectEqual(@as(usize, 3), board.squares[brd.getPos(0, 0)].len);
    try testing.expectEqual(brd.Color.White, board.squares[brd.getPos(0, 0)].stack[0].?.color);
    try testing.expectEqual(brd.Color.Black, board.squares[brd.getPos(0, 0)].stack[1].?.color);
    try testing.expectEqual(brd.Color.White, board.squares[brd.getPos(0, 0)].stack[2].?.color);
}

test "standing blocker" {
    const board = tps.parseTPS("[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]") catch unreachable;
    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 500);
    defer move_list.deinit();

    const move = brd.Move.createSlideMove(brd.getPos(3, 1), .North, 0b00000001);
    const move_string = ptn.moveToString(&allocator, move, brd.Color.White) catch unreachable;
    defer testing.allocator.free(move_string);
    // std.debug.print("Testing move: {s}\n", .{move_string});

    const steps = magic.numSteps(&board, brd.getPos(3, 1), .North);
    try testing.expectEqual(@as(usize, 4), steps);
}

test "standing stone slide" {
    const board = tps.parseTPS("[TPS 2,2,21S,2,2,2/x6/x6/x6/x6/x6 1 42]") catch unreachable;

    const move = brd.Move.createSlideMove(brd.getPos(2, 5), .East, 0b00000011);
    var allocator = testing.allocator;
    const move_string = ptn.moveToString(&allocator, move, brd.Color.White) catch unreachable;
    defer testing.allocator.free(move_string);
    // std.debug.print("Testing move: {s}\n", .{move_string});

    // const problem = board.squares[33].top().?;
    // std.debug.print("Top piece at position 33: type={}, color={}\n", .{problem.stone_type, problem.color});


    try moves.checkMove(board, move);
}

test "lots of standing stones" {
    const tps_string = "[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]";

    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 1000);
    defer move_list.deinit();

    const board = tps.parseTPS(tps_string) catch unreachable;

    try moves.generateMoves(&board, &move_list);

    for (move_list.moves[0..move_list.count]) |move| {
        const move_string = ptn.moveToString(&allocator, move, board.to_move) catch unreachable;
        defer testing.allocator.free(move_string);
        // std.debug.print("Generated move: {s}\n", .{move_string});
    }

    try testing.expectEqual(@as(usize, 18), move_list.count);
}

test "crush slide generating" {
    const tps_string = "[TPS x5,2S/1,x4,1C/x6/x6/2,x5/x6 1 3]";
    var allocator = testing.allocator;
    var move_list = try moves.MoveList.init(&allocator, 1000);
    defer move_list.deinit();
    const board = tps.parseTPS(tps_string) catch unreachable;
    try moves.generateMoves(&board, &move_list);
    try testing.expectEqual(@as(usize, 70), move_list.count);
}
