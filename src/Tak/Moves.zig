const std = @import("std");
const brd = @import("Board.zig");
const sym = @import("Sympathy.zig");

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

}
