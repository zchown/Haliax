const std = @import("std");
const brd = @import("board.zig");
const sym = @import("sympathy.zig");
const zob = @import("zobrist.zig");

pub const MoveList = struct {
    moves: []brd.Move,
    count: usize,
    capacity: usize,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator, initial_capacity: usize) !MoveList {
        const moves = try allocator.alloc(brd.Move, initial_capacity);
        return MoveList{
            .moves = moves,
            .count = 0,
            .capacity = initial_capacity,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MoveList) void {
        self.allocator.free(self.moves);
        self.moves = &[_]brd.Move{};
        self.count = 0;
        self.capacity = 0;
    }

    pub fn resize(self: *MoveList, new_capacity: usize) !void {
        const new_moves = try self.allocator.alloc(brd.Move, new_capacity);
        std.mem.copy(brd.Move, new_moves[0..self.count], self.moves[0..self.count]);
        self.allocator.free(self.moves);
        self.moves = new_moves;
        self.capacity = new_capacity;
    }

    pub fn append(self: *MoveList, move: brd.Move) !void {
        if (self.count >= self.capacity) {
            try self.resize(self.allocator, self.capacity * 2);
        }
        self.moves[self.count] = move;
        self.count += 1;
    }

    pub fn clear(self: *MoveList) void {
        self.count = 0;
    }

    pub inline fn appendUnsafe(self: *MoveList, move: brd.Move) void {
        self.moves[self.count] = move;
        self.count += 1;
    }
};

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
    board.crushMoves[board.half_move_count % brd.crush_map_size] = .NoCrush;
    board.half_move_count -= 1;
}

pub fn generateMoves(board: *const brd.Board, moves: *MoveList) !void {

    if (board.half_move_count < 2) {
        for (0..brd.board_size * brd.board_size) |pos| {
            if (brd.getBit(board.empty_squares, pos)) {
                // will always have at least this much capacity to start
                moves.appendUnsafe(brd.Move{
                    .position = pos,
                    .pattern = 0,
                    .flag = @as(u8, brd.StoneType.Flat),
                });
            }
        }
        return;
    }

    try generatePlaceMoves(board, moves);
    try generateSlideMoves(board, moves);
}

fn generatePlaceMoves(board: *const brd.Board, moves: *MoveList) !void {
    const color: brd.Color = board.to_move;
    for (0..brd.board_size * brd.board_size) |pos| {
        if (brd.getBit(board.empty_squares, pos)) {
            if (color == brd.Color.White) {
                if (board.white_stones_remaining > 0) {
                    moves.appendUnsafe(brd.Move{
                        .position = pos,
                        .pattern = 0,
                        .flag = @as(u8, brd.StoneType.Flat),
                    });
                    moves.appendUnsafe(brd.Move{
                        .position = pos,
                        .pattern = 0,
                        .flag = @as(u8, brd.StoneType.Standing),
                    });
                }
                if (board.white_capstones > 0) {
                    moves.appendUnsafe(brd.Move{
                        .position = pos,
                        .pattern = 0,
                        .flag = @as(u8, brd.StoneType.Capstone),
                    });
                }
            } else {
                if (board.black_stones_remaining > 0) {
                    moves.appendUnsafe(brd.Move{
                        .position = pos,
                        .pattern = 0,
                        .flag = @as(u8, brd.StoneType.Flat),
                    });
                    moves.appendUnsafe(brd.Move{
                        .position = pos,
                        .pattern = 0,
                        .flag = @as(u8, brd.StoneType.Standing),
                    });
                }
                if (board.black_capstones > 0) {
                    moves.appendUnsafe(brd.Move{
                        .position = pos,
                        .pattern = 0,
                        .flag = @as(u8, brd.StoneType.Capstone),
                    });
                }
            }
        }
    }
}

fn generateSlideMoves(board: *const brd.Board, moves: *MoveList) !void {
    const color: brd.Color = board.to_move;
    const color_bits = if (color == brd.Color.White) board.white_control else board.black_control;

    for (0..brd.board_size * brd.board_size) |pos| {
        if (!brd.getBit(color_bits, pos)) {
            continue;
        }
        var can_crush: bool = false;
        if (board.squares[pos].top()) |top_stone| {
            if (top_stone.stone_type == brd.StoneType.Capstone) {
                can_crush = true;
            }
        }

        const max_pickup = board.squares[pos].len;

        for (brd.Direction) |dir| {
            const max_steps = numSteps(board, pos, dir);
            var doing_crush: bool = false;

            // check if we can crush at the end
            if (can_crush and max_steps < brd.max_pickup) {
                if (brd.nthPositionFrom(pos, dir, max_steps)) |end_pos| {
                    if (board.squares[end_pos].top()) |stone| {
                        if (stone.stone_type == brd.StoneType.Standing) {
                            doing_crush = true;
                        }
                    }
                }
            }

            const patterns = sym.patterns.patterns[max_pickup - 1][max_steps - 1];
            if (moves.count + patterns.len > moves.capacity) {
                try moves.resize(moves.capacity * 2);
            }
            for (0..patterns.len) |pattern| {
                moves.appendUnsafe(brd.Move{
                    .position = pos,
                    .pattern = pattern,
                    .flag = @as(u8, dir),
                });
            }

            if (doing_crush) {
                const crush_patterns = sym.patterns.crush_patterns[max_pickup - 1][max_steps - 1];
                if (moves.count + crush_patterns.len > moves.capacity) {
                    try moves.resize(moves.capacity * 2);
                }

                for (0..crush_patterns.len) |pattern| {
                    moves.appendUnsafe(brd.Move{
                        .position = pos,
                        .pattern = pattern,
                        .flag = @as(u8, dir),
                    });
                }
            }
        }
    }
}

fn numSteps(board: *const brd.Board, start: brd.Position, dir: brd.Direction) usize {
    var steps: usize = 0;
    var cur_pos = brd.nextPosition(start, dir) orelse return steps;
    var pos_bit: brd.Bitboard = brd.positionBit(cur_pos);

    for (0..brd.max_pickup) |_| {
        if ((board.standing_stones | board.capstones) & pos_bit != 0) {
            return steps;
        }
        steps += 1;
        cur_pos = brd.nextPosition(cur_pos, dir) orelse return steps;
        switch (dir) {
            .North => pos_bit <<= brd.board_size,
            .South => pos_bit >>= brd.board_size,
            .East => pos_bit <<= 1,
            .West => pos_bit >>= 1,
        }
    }
}
