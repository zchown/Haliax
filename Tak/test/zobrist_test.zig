const std = @import("std");
const brd = @import("board");
const zob = @import("zobrist");
const moves = @import("moves");
const testing = std.testing;

test "computeZobristHash - empty board" {
    var board = brd.Board.init();
    const hash1 = board.zobrist_hash;

    zob.computeZobristHash(&board);
    const hash2 = board.zobrist_hash;

    try testing.expectEqual(hash1, hash2);
}

test "computeZobristHash - with single piece" {
    var board1 = brd.Board.init();
    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.computeZobristHash(&board1);

    var board2 = brd.Board.init();
    board2.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.computeZobristHash(&board2);

    try testing.expectEqual(board1.zobrist_hash, board2.zobrist_hash);
}

test "computeZobristHash - different pieces" {
    var board1 = brd.Board.init();
    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.computeZobristHash(&board1);

    var board2 = brd.Board.init();
    board2.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });
    zob.computeZobristHash(&board2);

    try testing.expect(board1.zobrist_hash != board2.zobrist_hash);
}

test "computeZobristHash - different positions" {
    var board1 = brd.Board.init();
    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.computeZobristHash(&board1);

    var board2 = brd.Board.init();
    board2.squares[brd.getPos(1, 1)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.computeZobristHash(&board2);

    try testing.expect(board1.zobrist_hash != board2.zobrist_hash);
}

test "computeZobristHash - different stone types" {
    var board1 = brd.Board.init();
    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.computeZobristHash(&board1);

    var board2 = brd.Board.init();
    board2.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Standing,
        .color = .White,
    });
    zob.computeZobristHash(&board2);

    try testing.expect(board1.zobrist_hash != board2.zobrist_hash);
}

test "computeZobristHash - stacked pieces" {
    var board1 = brd.Board.init();
    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });
    zob.computeZobristHash(&board1);

    var board2 = brd.Board.init();
    board2.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });
    board2.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.computeZobristHash(&board2);

    try testing.expect(board1.zobrist_hash != board2.zobrist_hash);
}

test "updateZobristHash - place move" {
    var board = brd.Board.init();
    const initial_hash = board.zobrist_hash;

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    board.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });

    zob.updateZobristHash(&board, move);

    try testing.expect(board.zobrist_hash != initial_hash);
}

test "updateZobristHash - place and undo" {
    var board = brd.Board.init();
    const initial_hash = board.zobrist_hash;

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);

    board.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.updateZobristHash(&board, move);
    const after_place = board.zobrist_hash;

    zob.updateZobristHash(&board, move);

    try testing.expectEqual(initial_hash, board.zobrist_hash);
    try testing.expect(after_place != initial_hash);
}

test "updateZobristHash matches computeZobristHash" {
    var board1 = brd.Board.init();
    var board2 = brd.Board.init();

    const move = brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat);
    moves.makeMove(&board1, move);

    board2.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });
    board2.to_move = .Black;
    board2.half_move_count = 1;
    zob.computeZobristHash(&board2);

    try testing.expectEqual(board1.zobrist_hash, board2.zobrist_hash);
}

test "zobrist hash collision resistance" {
    var board1 = brd.Board.init();
    var board2 = brd.Board.init();
    var board3 = brd.Board.init();

    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });

    board2.squares[brd.getPos(5, 5)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });

    board3.squares[brd.getPos(2, 3)].push(brd.Piece{
        .stone_type = .Capstone,
        .color = .Black,
    });

    zob.computeZobristHash(&board1);
    zob.computeZobristHash(&board2);
    zob.computeZobristHash(&board3);

    try testing.expect(board1.zobrist_hash != board2.zobrist_hash);
    try testing.expect(board1.zobrist_hash != board3.zobrist_hash);
    try testing.expect(board2.zobrist_hash != board3.zobrist_hash);
}

test "zobrist hash with complex position" {
    var board = brd.Board.init();

    board.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    board.squares[brd.getPos(1, 1)].push(brd.Piece{
        .stone_type = .Standing,
        .color = .Black,
    });
    board.squares[brd.getPos(2, 2)].push(brd.Piece{
        .stone_type = .Capstone,
        .color = .White,
    });

    board.squares[brd.getPos(3, 3)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    board.squares[brd.getPos(3, 3)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });
    board.squares[brd.getPos(3, 3)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });

    zob.computeZobristHash(&board);
    const hash1 = board.zobrist_hash;

    zob.computeZobristHash(&board);
    const hash2 = board.zobrist_hash;

    try testing.expectEqual(hash1, hash2);
}

test "zobrist hash full game consistency" {
    var board = brd.Board.init();

    const moves_to_make = [_]brd.Move{
        brd.Move.createPlaceMove(brd.getPos(0, 0), .Flat),
        brd.Move.createPlaceMove(brd.getPos(5, 5), .Flat),
        brd.Move.createPlaceMove(brd.getPos(1, 1), .Flat),
        brd.Move.createPlaceMove(brd.getPos(4, 4), .Standing),
    };

    for (moves_to_make) |move| {
        // std.debug.print("Making move at position: {}\n", .{move.position});
        // std.debug.print("flag: {d}, pattern: {b}\n", .{move.flag, move.pattern});
        const before_hash = board.zobrist_hash;
        moves.makeMove(&board, move);
        const after_hash = board.zobrist_hash;

        try testing.expect(before_hash != after_hash);

        zob.computeZobristHash(&board);
        try testing.expectEqual(after_hash, board.zobrist_hash);
    }
}

test "zobrist hash after slide move" {
    var board = brd.Board.init();
    board.half_move_count = 2; 

    board.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    brd.setBit(&board.white_control, brd.getPos(0, 0));
    zob.computeZobristHash(&board);

    const before_hash = board.zobrist_hash;

    const move = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 0b00000001);
    moves.makeMove(&board, move);

    try testing.expect(board.zobrist_hash != before_hash);

    var verify_board = brd.Board.init();
    verify_board.half_move_count = board.half_move_count;
    for (0..brd.num_squares) |i| {
        verify_board.squares[i] = board.squares[i];
    }
    zob.computeZobristHash(&verify_board);
    try testing.expectEqual(board.zobrist_hash, verify_board.zobrist_hash);
}

test "zobrist hash symmetry" {
    var board = brd.Board.init();
    const initial = board.zobrist_hash;

    const move = brd.Move.createPlaceMove(brd.getPos(2, 2), .Flat);

    board.squares[brd.getPos(2, 2)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    zob.updateZobristHash(&board, move);
    zob.updateZobristHash(&board, move);

    try testing.expectEqual(initial, board.zobrist_hash);
}

test "zobrist different depths in stack" {
    var board1 = brd.Board.init();
    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    board1.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });
    zob.computeZobristHash(&board1);

    var board2 = brd.Board.init();
    board2.squares[brd.getPos(1, 1)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });
    board2.squares[brd.getPos(1, 1)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .Black,
    });
    zob.computeZobristHash(&board2);

    try testing.expect(board1.zobrist_hash != board2.zobrist_hash);
}
