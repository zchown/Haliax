const std = @import("std");
const brd = @import("board");
const tps = @import("tps");
const testing = std.testing;

test "Board initialization" {
    const b = brd.Board.init();

    try testing.expectEqual(@as(usize, brd.stone_count), b.white_stones_remaining);
    try testing.expectEqual(@as(usize, brd.stone_count), b.black_stones_remaining);
    try testing.expectEqual(@as(usize, brd.capstone_count), b.white_capstones_remaining);
    try testing.expectEqual(@as(usize, brd.capstone_count), b.black_capstones_remaining);
    try testing.expectEqual(brd.Color.White, b.to_move);
    try testing.expectEqual(@as(usize, 0), b.half_move_count);
    try testing.expectEqual(brd.board_mask, b.empty_squares);
    try testing.expectEqual(@as(brd.Bitboard, 0), b.white_control);
    try testing.expectEqual(@as(brd.Bitboard, 0), b.black_control);
}

test "Position conversions" {
    const pos = brd.getPos(2, 3);
    try testing.expectEqual(@as(usize, 2), brd.getX(pos));
    try testing.expectEqual(@as(usize, 3), brd.getY(pos));

    const pos2 = brd.getPos(0, 0);
    try testing.expectEqual(@as(usize, 0), brd.getX(pos2));
    try testing.expectEqual(@as(usize, 0), brd.getY(pos2));

    const pos3 = brd.getPos(5, 5);
    try testing.expectEqual(@as(usize, 5), brd.getX(pos3));
    try testing.expectEqual(@as(usize, 5), brd.getY(pos3));
}

test "Direction operations" {
    const pos = brd.getPos(2, 2);

    const north = brd.nextPosition(pos, .North);
    try testing.expect(north != null);
    try testing.expectEqual(@as(usize, 2), brd.getX(north.?));
    try testing.expectEqual(@as(usize, 3), brd.getY(north.?));

    const south = brd.nextPosition(pos, .South);
    try testing.expect(south != null);
    try testing.expectEqual(@as(usize, 2), brd.getX(south.?));
    try testing.expectEqual(@as(usize, 1), brd.getY(south.?));

    const east = brd.nextPosition(pos, .East);
    try testing.expect(east != null);
    try testing.expectEqual(@as(usize, 3), brd.getX(east.?));
    try testing.expectEqual(@as(usize, 2), brd.getY(east.?));

    const west = brd.nextPosition(pos, .West);
    try testing.expect(west != null);
    try testing.expectEqual(@as(usize, 1), brd.getX(west.?));
    try testing.expectEqual(@as(usize, 2), brd.getY(west.?));
}

test "Direction boundaries" {
    const top_left = brd.getPos(0, 5);
    try testing.expect(brd.nextPosition(top_left, .North) == null);
    try testing.expect(brd.nextPosition(top_left, .West) == null);

    const bottom_right = brd.getPos(5, 0);
    try testing.expect(brd.nextPosition(bottom_right, .South) == null);
    try testing.expect(brd.nextPosition(bottom_right, .East) == null);
}

test "Nth position from" {
    const pos = brd.getPos(0, 0);

    const north3 = brd.nthPositionFrom(pos, .North, 3);
    try testing.expect(north3 != null);
    try testing.expectEqual(@as(usize, 0), brd.getX(north3.?));
    try testing.expectEqual(@as(usize, 3), brd.getY(north3.?));

    const east2 = brd.nthPositionFrom(pos, .East, 2);
    try testing.expect(east2 != null);
    try testing.expectEqual(@as(usize, 2), brd.getX(east2.?));
    try testing.expectEqual(@as(usize, 0), brd.getY(east2.?));

    const too_far = brd.nthPositionFrom(pos, .East, 10);
    try testing.expect(too_far == null);
}

test "Bitboard operations" {
    var bb: brd.Bitboard = 0;

    brd.setBit(&bb, 0);
    try testing.expect(brd.getBit(bb, 0));
    try testing.expectEqual(@as(u32, 1), brd.countBits(bb));

    brd.setBit(&bb, 5);
    try testing.expect(brd.getBit(bb, 5));
    try testing.expectEqual(@as(u32, 2), brd.countBits(bb));

    brd.clearBit(&bb, 0);
    try testing.expect(!brd.getBit(bb, 0));
    try testing.expectEqual(@as(u32, 1), brd.countBits(bb));
}

test "Square operations" {
    var square = brd.Square.init();

    try testing.expectEqual(@as(usize, 0), square.len);
    try testing.expect(square.top() == null);

    const white_flat = brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    };

    square.push(white_flat);
    try testing.expectEqual(@as(usize, 1), square.len);
    try testing.expectEqual(@as(usize, 1), square.white_count);
    try testing.expectEqual(@as(usize, 0), square.black_count);

    const top = square.top();
    try testing.expect(top != null);
    try testing.expectEqual(brd.StoneType.Flat, top.?.stone_type);
    try testing.expectEqual(brd.Color.White, top.?.color);

    const black_cap = brd.Piece{
        .stone_type = .Capstone,
        .color = .Black,
    };

    square.push(black_cap);
    try testing.expectEqual(@as(usize, 2), square.len);
    try testing.expectEqual(@as(usize, 1), square.white_count);
    try testing.expectEqual(@as(usize, 1), square.black_count);

    try square.remove(1);
    try testing.expectEqual(@as(usize, 1), square.len);
    try testing.expectEqual(@as(usize, 0), square.black_count);
}

test "Color opposite" {
    try testing.expectEqual(brd.Color.Black, brd.Color.White.opposite());
    try testing.expectEqual(brd.Color.White, brd.Color.Black.opposite());
}

test "Move creation" {
    const place_move = brd.Move.createPlaceMove(brd.getPos(2, 3), .Flat);
    try testing.expectEqual(brd.getPos(2, 3), place_move.position);
    try testing.expectEqual(@as(u2, 0), place_move.flag);
    try testing.expectEqual(@as(u8, 0), place_move.pattern);

    const slide_move = brd.Move.createSlideMove(brd.getPos(1, 1), .North, 0b11000000);
    try testing.expectEqual(brd.getPos(1, 1), slide_move.position);
    try testing.expectEqual(@as(u2, 0), slide_move.flag);
    try testing.expectEqual(@as(u8, 0b11000000), slide_move.pattern);
}

test "Move equality" {
    const move1 = brd.Move.createPlaceMove(brd.getPos(2, 3), .Flat);
    const move2 = brd.Move.createPlaceMove(brd.getPos(2, 3), .Flat);
    const move3 = brd.Move.createPlaceMove(brd.getPos(2, 3), .Standing);

    try testing.expect(brd.movesEqual(move1, move2));
    try testing.expect(!brd.movesEqual(move1, move3));
}

test "Moved stones count" {
    const move1 = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 0b11000000);
    try testing.expectEqual(@as(usize, 2), move1.movedStones());

    const move2 = brd.Move.createSlideMove(brd.getPos(0, 0), .East, 0b11100000);
    try testing.expectEqual(@as(usize, 3), move2.movedStones());

    const move3 = brd.Move.createSlideMove(brd.getPos(0, 0), .South, 0b10000000);
    try testing.expectEqual(@as(usize, 1), move3.movedStones());
}

test "Board equality" {
    var board1 = brd.Board.init();
    var board2 = brd.Board.init();

    try testing.expect(board1.equals(&board2));

    board1.white_stones_remaining -= 1;
    try testing.expect(board1.equals(&board2));
}

test "Empty square check" {
    var board = brd.Board.init();

    try testing.expect(board.isSquareEmpty(brd.getPos(0, 0)));
    try testing.expect(board.isSquareEmpty(brd.getPos(5, 5)));

    board.squares[brd.getPos(0, 0)].push(brd.Piece{
        .stone_type = .Flat,
        .color = .White,
    });

    try testing.expect(!board.isSquareEmpty(brd.getPos(0, 0)));
}

test "Opposite direction" {
    try testing.expectEqual(brd.Direction.South, brd.opositeDirection(.North));
    try testing.expectEqual(brd.Direction.North, brd.opositeDirection(.South));
    try testing.expectEqual(brd.Direction.West, brd.opositeDirection(.East));
    try testing.expectEqual(brd.Direction.East, brd.opositeDirection(.West));
}

test "Board mask generation" {
    const mask = brd.board_mask;
    try testing.expectEqual(@as(u32, brd.num_squares), brd.countBits(mask));
}

test "Row and column masks" {
    for (brd.row_masks) |mask| {
        try testing.expectEqual(@as(u32, brd.board_size), brd.countBits(mask));
    }

    for (brd.column_masks) |mask| {
        try testing.expectEqual(@as(u32, brd.board_size), brd.countBits(mask));
    }

    for (0..brd.board_size) |i| {
        for (i + 1..brd.board_size) |j| {
            try testing.expectEqual(@as(brd.Bitboard, 0), brd.row_masks[i] & brd.row_masks[j]);
        }
    }

    for (0..brd.board_size) |i| {
        for (i + 1..brd.board_size) |j| {
            try testing.expectEqual(@as(brd.Bitboard, 0), brd.column_masks[i] & brd.column_masks[j]);
        }
    }
}

test "Is on board" {
    try testing.expect(brd.isOnBoard(0, 0));
    try testing.expect(brd.isOnBoard(5, 5));
    try testing.expect(brd.isOnBoard(2, 3));

    try testing.expect(!brd.isOnBoard(-1, 0));
    try testing.expect(!brd.isOnBoard(0, -1));
    try testing.expect(!brd.isOnBoard(6, 0));
    try testing.expect(!brd.isOnBoard(0, 6));
    try testing.expect(!brd.isOnBoard(10, 10));
}

test "LSB extraction" {
    var bb: brd.Bitboard = 0;
    brd.setBit(&bb, 5);
    try testing.expectEqual(@as(brd.Position, 5), brd.getLSB(bb));

    brd.setBit(&bb, 3);
    try testing.expectEqual(@as(brd.Position, 3), brd.getLSB(bb));
}

