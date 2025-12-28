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

    square.pushPiece(white_flat);
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

    square.pushPiece(black_cap);
    try testing.expectEqual(@as(usize, 2), square.len);
    try testing.expectEqual(@as(usize, 1), square.white_count);
    try testing.expectEqual(@as(usize, 1), square.black_count);

    try square.removePieces(1);
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
    const move1 = brd.Move.createSlideMove(brd.getPos(0, 0), .North, 0b00000011);
    try testing.expectEqual(@as(usize, 2), move1.movedStones());

    const move2 = brd.Move.createSlideMove(brd.getPos(0, 0), .East, 0b00000100);
    try testing.expectEqual(@as(usize, 3), move2.movedStones());

    const move3 = brd.Move.createSlideMove(brd.getPos(0, 0), .South, 0b00000001);
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

    board.pushPieceToSquare(brd.getPos(0, 0), brd.Piece{
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

test "full tests" {
    const tps_str = "[TPS 1,1,1,1,1,1/1,1,1,1,1,1/1,1,1,1,1,1/1,1,1,1,1,1/1,1,1,1,1,1/1,1,1,1,1,1 1 1]";
    var board = try tps.parseTPS(tps_str);

    const expected = brd.Result{
        .road = 0,
        .flat = 1,
        .color = 0,
        .ongoing = 0,
    };

    try testing.expectEqual(expected, board.checkResult());
}

test "Check hard roads" {
    // Test 1: Game should continue (no road yet)
    const tps_str1 = "[TPS 1,x3,2C,x/1,x2,2,x2/1,1,1,2,2S,x/1,x,1,x3/2,x,1,x3/x,x,2,x3 2 1]";
    var board1 = try tps.parseTPS(tps_str1);
    const result1 = board1.checkResult();

    const expected1 = brd.Result{
        .road = 0,
        .flat = 0,
        .color = 0,
        .ongoing = 1,
    };
    try testing.expectEqual(expected1, result1);

    // Test 2: Black road win (vertical column of black stones)
    const tps_str2 = "[TPS 2,x5/2,x5/2,x5/2,x5/2,x5/2,x5 2 2]";
    var board2 = try tps.parseTPS(tps_str2);
    const result2 = board2.checkResult();

    const expected2 = brd.Result{
        .road = 1,
        .flat = 0,
        .color = 1,
        .ongoing = 0,
    };
    try testing.expectEqual(expected2, result2);

    // Test 3: Black road win (complex road pattern)
    const tps_str3 = "[TPS x6/x6/x6/x,212121,x4/22,12,2,2,2,12/x6 1 31]";
    var board3 = try tps.parseTPS(tps_str3);
    const result3 = board3.checkResult();

    const expected3 = brd.Result{
        .road = 1,
        .flat = 0,
        .color = 1,
        .ongoing = 0,
    };
    try testing.expectEqual(expected3, result3);

    // Test 4: Game should continue (single stone in corner, no road)
    const tps_str4 = "[TPS x6/x6/x6/x6/x6/x5,1 2 2]";
    var board4 = try tps.parseTPS(tps_str4);
    const result4 = board4.checkResult();

    const expected4 = brd.Result{
        .road = 0,
        .flat = 0,
        .color = 0,
        .ongoing = 1,
    };
    try testing.expectEqual(expected4, result4);

    // Test 5: White flat win (all standing stones blocking, no roads)
    const tps_str5 = "[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,2,1,1,1,1 2 6]";
    var board5 = try tps.parseTPS(tps_str5);
    const result5 = board5.checkResult();

    const expected5 = brd.Result{
        .road = 0,
        .flat = 1,
        .color = 0,
        .ongoing = 0,
    };
    try testing.expectEqual(expected5, result5);

    // Test 6: Horizontal road win for White
    const tps_str6 = "[TPS x6/1,1,1,1,1,1/x6/x6/x6/x5,1 2 2]";
    var board6 = try tps.parseTPS(tps_str6);
    const result6 = board6.checkResult();

    const expected6 = brd.Result{
        .road = 1,
        .flat = 0,
        .color = 0,
        .ongoing = 0,
    };
    try testing.expectEqual(expected6, result6);

    // Test 7
    const tps_str7 = "[TPS 2,x2,2221,x2/x2,1,21,x2/2221S,2,21C,1,2,2/1,1,1,1,2S,1/1,12,1,1112C,1,1/1,x,2S,x2,1 2 30]";
    var board7 = try tps.parseTPS(tps_str7);
    const result7 = board7.checkResult();

    const expected7 = brd.Result{
        .road = 1,
        .flat = 0,
        .color = 0,
        .ongoing = 0,
    };
    try testing.expectEqual(expected7, result7);

    // Test 8
    const tps_str8 = "[TPS 2,12,1,2,22221S,2/1,2,211111,1212C,x,121212S/x,1,21C,2,2,x/1,1,1,2,212,1S/1,1,1S,x,2,x/1,x2,2,2,x 1 39]";
    var board8 = try tps.parseTPS(tps_str8);
    const result8 = board8.checkResult();

    const expected8 = brd.Result{
        .road = 1,
        .flat = 0,
        .color = 1,
        .ongoing = 0,
    };
    try testing.expectEqual(expected8, result8);

    // Test 9
    const tps_str9 = "[TPS 1,x5/x,2,x,2,x2/1,1,12C,221S,x2/2S,1C,1,1121,1,1/x,2,x4/2,x2,12,x2 2 17]";
    var board9 = try tps.parseTPS(tps_str9);
    const result9 = board9.checkResult();

    const expected9 = brd.Result{
        .road = 1,
        .flat = 0,
        .color = 0,
        .ongoing = 0,
    };
    try testing.expectEqual(expected9, result9);

    // Test 10
    const tps_str10 = "[TPS x,2,1,2,1,x/2,2,1,1,111221,2S/1,21,221C,112C,1,2/12,2,2S,x,1,1/1,1,1,12S,x2/2,1,x4 2 27]";
    var board10 = try tps.parseTPS(tps_str10);
    const result10 = board10.checkResult();

    const expected10 = brd.Result{
        .road = 1,
        .flat = 0,
        .color = 0,
        .ongoing = 0,
    };
    try testing.expectEqual(expected10, result10);

    // Test 11
    const tps_str11 = "[TPS 1,x3,2,21S/12112112C,1,1,2,2,2/x4,1,2/x2,1,1,x,2/x,21C,1221,2,x,2/x2,1,x2,2 1 25]";
    var board11 = try tps.parseTPS(tps_str11);
    const result11 = board11.checkResult();

    const expected11 = brd.Result{
        .road = 1,
        .flat = 0,
        .color = 1,
        .ongoing = 0,
    };
    try testing.expectEqual(expected11, result11);

    // Test 13
    const tps_str13 = "[TPS 2,x2,221S,x,2/x,121S,212S,2,21S,2/21,2,1,2,2,2111112C/2,2,21C,1,2,1/1,21S,1,211112S,2,1/2,x2,2,2,1 1 39]";
    var board13 = try tps.parseTPS(tps_str13);
    const result13 = board13.checkResult();
    const expected13 = brd.Result{ .road = 1, .flat = 0, .color = 1, .ongoing = 0 };
    try testing.expectEqual(expected13, result13);

    // Test 14
    const tps_str14 = "[TPS 2,x2,1,2,1/2,2,x,1,12,2/1,1,2221C,2,2,12/x,111112C,1,1,112S,1/x,1,2,1,1,1/x,1,2,2,x,1 2 28]";
    var board14 = try tps.parseTPS(tps_str14);
    const result14 = board14.checkResult();
    const expected14 = brd.Result{ .road = 1, .flat = 0, .color = 0, .ongoing = 0 };
    try testing.expectEqual(expected14, result14);

    // Test 15
    const tps_str15 = "[TPS 2,x3,1,1/2,2,2,1S,2,x/x,2,21221C,2,1112C,12/x,2,2,1,1,1/x,21,2,x2,1/x2,2,x2,1 1 22]";
    var board15 = try tps.parseTPS(tps_str15);
    const result15 = board15.checkResult();
    const expected15 = brd.Result{ .road = 1, .flat = 0, .color = 1, .ongoing = 0 };
    try testing.expectEqual(expected15, result15);

    // Test 16
    const tps_str16 = "[TPS 2,x,1,2,x2/x,2,1,2,x2/x3,2,x2/2,212,2S,112C,x,1/21C,221,1,12S,1,x/2S,1,1,1,1,1 2 22]";
    var board16 = try tps.parseTPS(tps_str16);
    const result16 = board16.checkResult();
    const expected16 = brd.Result{ .road = 1, .flat = 0, .color = 0, .ongoing = 0 };
    try testing.expectEqual(expected16, result16);

    // Test 17
    const tps_str17 = "[TPS 1,2221C,1,2,1,1/12112S,2,1,1,1,x/x4,1,2/2,21,x,2,12C,2/x,2,2,x,1,x/2,x5 2 21]";
    var board17 = try tps.parseTPS(tps_str17);
    const result17 = board17.checkResult();
    const expected17 = brd.Result{ .road = 1, .flat = 0, .color = 0, .ongoing = 0 };
    try testing.expectEqual(expected17, result17);

    // Test 18
    const tps_str18 = "[TPS 1,12,x,2,x2/2,12S,1,2,1S,x/1,x,121C,2,12112S,x/2,11112C,21,2,2,x/1,1,x,2,x2/1,1,x,2,x2 1 27]";
    var board18 = try tps.parseTPS(tps_str18);
    const result18 = board18.checkResult();
    const expected18 = brd.Result{ .road = 1, .flat = 0, .color = 1, .ongoing = 0 };
    try testing.expectEqual(expected18, result18);
}
