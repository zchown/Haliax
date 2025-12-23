const std = @import("std");
const brd = @import("Board.zig");
const sym = @import("Sympathy.zig");
const zob = @import("Zobrist.zig");

pub const MoveError = error{
    InvalidMove,
    InvalidPosition,
    InvalidDirection,
    InvalidPattern,
    InvalidStone,
    InvalidColor,
    InvalidMoveType,
    InvalidCount,
    InvalidCrush,
    InvalidSlide,
    InvalidDrops,
};

pub fn checkMove(board: brd.Board, move: brd.Move) MoveError!void {
    const color: brd.Color = board.to_move;

    if (!brd.isOnBoard(move.position)) {
        return MoveError.InvalidPosition;
    }

    // place move
    if (move.pattern == 0) {
        if (board.isSquareEmpty(move.position) == false) {
            return MoveError.InvalidPosition;
        }
        if (move.flag == brd.StoneType.Capstone) {
            if (color == brd.Color.White and board.white_capstones == 0) {
                return MoveError.InvalidStone;
            } else if (color == brd.Color.Black and board.black_capstones == 0) {
                return MoveError.InvalidStone;
            }
        }
        else if (move.flag == brd.StoneType.Standing) {
            if (color == brd.Color.White and board.white_standing == 0) {
                return MoveError.InvalidStone;
            } else if (color == brd.Color.Black and board.black_standing == 0) {
                return MoveError.InvalidStone;
            }
        }
        else if (move.flag == brd.StoneType.Flat) {
            if (color == brd.Color.White and board.white_flats == 0) {
                return MoveError.InvalidStone;
            } else if (color == brd.Color.Black and board.black_flats == 0) {
                return MoveError.InvalidStone;
            }
        } else {
            return MoveError.InvalidStone;
        }
        // valid place move
        return;
    }
    // slide move
    const dir: brd.Direction = @enumFromInt(move.flag);
    const length: usize = @popCount(move.pattern);
    const end_pos = brd.nthPositionFrom(move.position, dir, length) orelse return MoveError.InvalidPattern;

    if (board.squares[move.position].len < length) {
        return MoveError.InvalidCount;
    }

    const top_stone = board.squares[move.position].top() orelse return MoveError.InvalidCount;

    if (top_stone.color != board.to_move) {
        return MoveError.InvalidColor;
    }

    const end_square_stone = board.squares[end_pos].top();

    if (end_square_stone) |stone| {
        if (stone.stone_type == brd.StoneType.Standing) {
            if (top_stone != brd.StoneType.Capstone) {
                return MoveError.InvalidCrush;
            }
            else {
                // check that last bit in pattern is a 1
                if ((move.pattern & 0x1) == 0) {
                    return MoveError.InvalidCrush;
                }
            }
        }
    }

    var cur_pos = move.position;
    for (0..length) |_| {
        if (board.squares[move.position].top()) |stone| {
            if (stone.stone_type == brd.StoneType.Standing) {
                return MoveError.InvalidSlide;
            }
        }
        cur_pos = brd.nextPosition(cur_pos, dir) orelse return MoveError.InvalidPattern;
    }

}

pub fn makeMoveWithCheck(board: *brd.Board, move: brd.Move) MoveError!void {
    try checkMove(board.*, move);
    makeMove(board, move);
}

pub fn makeMove(board: *brd.Board, move: brd.Move) !void {
    zob.updateZobristHash(board, move);

    if (move.pattern == 0) {

        const place_color = if (board.half_move_count < 2) brd.to_move.opposite() else board.to_move;

        board.squares[move.position].push(brd.Stone{
            .color = place_color,
            .stone_type = @enumFromInt(move.flag),
        });

        if (board.to_move == brd.Color.White) {
            brd.setBit(&board.white_control, move.position);
        }
        else {
            brd.setBit(&board.black_control, move.position);
        }

        brd.clearBit(&board.empty_squares, move.position);

        switch (@as(brd.StoneType, @enumFromInt(move.flag))) {
            .Flat => {
                if (board.to_move == brd.Color.White) {
                    board.white_flats -= 1;
                } else {
                    board.black_flats -= 1;
                }
            },
            .Standing => {
                brd.setBit(&board.standing_squares, move.position);
                if (board.to_move == brd.Color.White) {
                    board.white_standing -= 1;
                } else {
                    board.black_standing -= 1;
                }
            },
            .Capstone => {
                brd.setBit(&board.capstone_squares, move.position);
                if (board.to_move == brd.Color.White) {
                    board.white_capstones -= 1;
                } else {
                    board.black_capstones -= 1;
                }
            },
        }
        return;
    }

    // slide move
    const dir: brd.Direction = @enumFromInt(move.flag);
    const length: usize = @popCount(move.pattern);
    const end_pos: brd.Position = try brd.nthPositionFrom(move.position, dir, length);

    // crush if needed
    if (board.squares[end_pos].top()) |stone| {
        if (stone.stone_type == brd.StoneType.Standing) {
            board.squares[end_pos].stack[board.squares[end_pos].len - 1].stone_type = brd.StoneType.Flat;
            board.crushMoves[board.half_move_count % brd.crush_map_size] = .Crush;
        }
    }

    // keep track of if we have moved yet
    var started: bool = false;
    var cur_pos: brd.Position = move.position;
    const diff: usize = 8 - brd.max_pickup;
    // iterate over pattern bits
    for (0..8) |i| {
        const bit = (move.pattern >> (7 - i)) & 0x1;

        if (!started) {
            if (bit == 1) {
                started = true;
            } else {
                continue;
            }
        }

        if (bit == 1) {
            cur_pos = try brd.nextPosition(cur_pos, dir);
        }

        const to_move: brd.Piece = board.squares[move.position].stack[board.squares[move.position].len - 1 - (i - diff)];
        board.squares[cur_pos].push(to_move);
    }

    // remove moved stones from original position
    board.squares[move.position].remove(move.movedStones());
    board.to_move = board.to_move.opposite();
    board.half_move_count += 1;
}

pub fn checkUndoMove(board: brd.Board, move: brd.Move) MoveError!void {
    const color: brd.Color = board.to_move.opposite();

    if (!brd.isOnBoard(move.position)) {
        return MoveError.InvalidPosition;
    }

    if (move.pattern == 0) {
        if (board.squares[move.position].len != 1) {
            return MoveError.InvalidPosition;
        }

        const top_stone = board.squares[move.position].top() orelse return MoveError.InvalidStone;

        if (top_stone.color != color and board.half_move_count >= 2) {
            return MoveError.InvalidColor;
        } 
        else if (top_stone.color == color and board.half_move_count < 2) {
            return MoveError.InvalidColor;
        }

        if (top_stone.stone_type != @as(brd.StoneType, @enumFromInt(move.flag))) {
            return MoveError.InvalidStone;
        }

        return;
    }

    const dir: brd.Direction = @enumFromInt(move.flag);
    const length: usize = @popCount(move.pattern);
    const end_pos = brd.nthPositionFrom(move.position, dir, length) orelse return MoveError.InvalidPattern;

    if (board.squares[end_pos].top()) |stone| {
        if (board.typeof(stone.stone_type) == brd.StoneType.Standing) {
            return MoveError.InvalidMove;
        }
    }

    // Reconstruct the list of destination positions used during the original slide.
    var positions: [8]brd.Position = undefined;
    var idx: usize = 0;
    var started: bool = false;
    var cur_pos: brd.Position = move.position;

    for (0..8) |i| {
        const bit = (move.pattern >> (7 - i)) & 0x1;

        if (!started) {
            if (bit == 1) {
                started = true;
            } else {
                continue;
            }
        }

        if (bit == 1) {
            cur_pos = brd.nextPosition(cur_pos, dir) orelse return MoveError.InvalidPattern;
        }

        positions[idx] = cur_pos;
        idx += 1;

        if (idx == length) break;
    }

    if (idx != length) return MoveError.InvalidPattern;

    for (positions[0..idx]) |p| {
        var needed: usize = 0;
        for (positions[0..idx]) |q| {
            if (q == p) needed += 1;
        }
        if (board.squares[p].len < needed) {
            return MoveError.InvalidCount;
        }
    }

    return;
}

pub fn undoMoveWithCheck(board: *brd.Board, move: brd.Move) MoveError!void {
    try checkUndoMove(board.*, move);
    try undoMove(board, move);
}

pub fn undoMove(board: *brd.Board, move: brd.Move) MoveError!void {
    zob.updateZobristHash(board, move);

    if (move.pattern == 0) {
        const color: brd.Color = board.to_move.opposite();

        const top_stone = board.squares[move.position].top() orelse return MoveError.InvalidStone;

        const popped: brd.Piece = top_stone;
        board.squares[move.position].remove(1);

        brd.setBit(&board.empty_squares, move.position);
        if (color == brd.Color.White) {
            brd.clearBit(&board.white_control, move.position);
        } else {
            brd.clearBit(&board.black_control, move.position);
        }

        switch (popped.stone_type) {
            .Flat => {
                if (color == brd.Color.White) {
                    board.white_flats += 1;
                } else {
                    board.black_flats += 1;
                }
            },
            .Standing => {
                brd.clearBit(&board.standing_squares, move.position);
                if (color == brd.Color.White) {
                    board.white_standing += 1;
                } else {
                    board.black_standing += 1;
                }
            },
            .Capstone => {
                brd.clearBit(&board.capstone_squares, move.position);
                if (color == brd.Color.White) {
                    board.white_capstones += 1;
                } else {
                    board.black_capstones += 1;
                }
            },
        }

        board.to_move = board.to_move.opposite();
        board.half_move_count -= 1;
        return;
    }

    // slide move
    const dir: brd.Direction = @enumFromInt(move.flag);
    const length: usize = @popCount(move.pattern);
    const end_pos = brd.nthPositionFrom(move.position, dir, length) orelse return MoveError.InvalidPattern;

    var positions: [8]brd.Position = undefined;
    var idx: usize = 0;
    var started: bool = false;
    var cur_pos: brd.Position = move.position;

    for (0..8) |i| {
        const bit = (move.pattern >> (7 - i)) & 0x1;

        if (!started) {
            if (bit == 1) {
                started = true;
            } else {
                continue;
            }
        }

        if (bit == 1) {
            cur_pos = try brd.nextPosition(cur_pos, dir);
        }

        positions[idx] = cur_pos;
        idx += 1;

        if (idx == length) break;
    }

    if (idx != length) return MoveError.InvalidPattern;

    var popped: [8]brd.Piece = undefined;
    var pidx: usize = 0;

    var j: isize = @as(isize, @intCast(idx)) - 1;
    while (j >= 0) : (j -= 1) {
        const pos = positions[@intCast(j)];

        if (board.squares[pos].len == 0) {
            return MoveError.InvalidCount;
        }

        const top_piece: brd.Piece = board.squares[pos].stack[board.squares[pos].len - 1];
        board.squares[pos].remove(1);
        popped[pidx] = top_piece;
        pidx += 1;
    }

    if (board.crushMoves[board.half_move_count % brd.crush_map_size] == .Crush) {
        if (board.squares[end_pos].top()) |_| {
            board.squares[end_pos].stack[board.squares[end_pos].len - 1].stone_type = brd.StoneType.Standing;
        }
    }

    var k: isize = @as(isize, @intCast(pidx)) - 1;
    while (k >= 0) : (k -= 1) {
        board.squares[move.position].push(popped[@intCast(k)]);
    }

    board.to_move = board.to_move.opposite();
    board.half_move_count -= 1;
}

