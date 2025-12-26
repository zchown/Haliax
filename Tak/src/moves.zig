const std = @import("std");
const brd = @import("board");
const sym = @import("sympathy");
const zob = @import("zobrist");

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
        std.mem.copyForwards(brd.Move, new_moves[0..self.count], self.moves[0..self.count]);
        self.allocator.free(self.moves);
        self.moves = new_moves;
        self.capacity = new_capacity;
    }

    pub fn append(self: *MoveList, move: brd.Move) !void {
        if (self.count >= self.capacity) {
            try self.resize(self.capacity * 2);
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

    if (!brd.isOnBoardPos(move.position)) {
        return MoveError.InvalidPosition;
    }

    // place move
    if (move.pattern == 0) {
        if (board.isSquareEmpty(move.position) == false) {
            return MoveError.InvalidPosition;
        }
        if (move.flag == @intFromEnum(brd.StoneType.Capstone)) {
            if (color == brd.Color.White and board.white_capstones_remaining == 0) {
                return MoveError.InvalidStone;
            } else if (color == brd.Color.Black and board.black_capstones_remaining == 0) {
                return MoveError.InvalidStone;
            }
        }
        else if (move.flag == @intFromEnum(brd.StoneType.Standing)) {
            if (color == brd.Color.White and board.white_stones_remaining == 0) {
                return MoveError.InvalidStone;
            } else if (color == brd.Color.Black and board.black_stones_remaining == 0) {
                return MoveError.InvalidStone;
            }
        }
        else if (move.flag == @intFromEnum(brd.StoneType.Flat)) {
            if (color == brd.Color.White and board.white_stones_remaining == 0) {
                return MoveError.InvalidStone;
            } else if (color == brd.Color.Black and board.black_stones_remaining == 0) {
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
        std.debug.print("Not enough stones to move: have {d}, need {d}\n", .{board.squares[move.position].len, length});
        std.debug.print("Move pattern: {b}\n", .{move.pattern});
        std.debug.print("From position: {d}\n", .{move.position});
        return MoveError.InvalidCount;
    }

    const top_stone = board.squares[move.position].top() orelse return MoveError.InvalidCount;

    if (top_stone.color != board.to_move) {
        return MoveError.InvalidColor;
    }

    const end_square_stone = board.squares[end_pos].top();

    if (end_square_stone) |stone| {
        if (stone.stone_type == brd.StoneType.Standing) {
            if (top_stone.stone_type != brd.StoneType.Capstone) {
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
    cur_pos = brd.nextPosition(cur_pos, dir) orelse return MoveError.InvalidPattern;
    for (0..length - 1) |_| {
        if (board.squares[cur_pos].top()) |stone| {
            if (stone.stone_type == brd.StoneType.Standing) {
                // std.debug.print("Cannot slide over standing stone at position {d}\n", .{cur_pos});
                // std.debug.print("Stone type: {}, color: {}\n", .{stone.stone_type, stone.color});
                // std.debug.print("Move pattern: {b}\n", .{move.pattern});
                // std.debug.print("Index: {d}\n", .{i});
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

pub fn makeMove(board: *brd.Board, move: brd.Move) void {
    var did_crush: bool = false;

    defer {
        board.to_move = board.to_move.opposite();
        board.half_move_count += 1;
        if (!did_crush) {
            // std.debug.print("No crush move made\n", .{});
            board.crushMoves[board.half_move_count % brd.crush_map_size] = .NoCrush;
        }
        zob.updateZobristHash(board, move);
    }
    if (move.pattern == 0) {

        const place_color = if (board.half_move_count < 2) board.to_move.opposite() else board.to_move;

        // board.squares[move.position].push(brd.Piece{
        //     .color = place_color,
        //     .stone_type = @enumFromInt(move.flag),
        // });
        board.pushPieceToSquare(move.position, brd.Piece{
            .color = place_color,
            .stone_type = @enumFromInt(move.flag),
        });

        // if (board.to_move == brd.Color.White) {
        //     brd.setBit(&board.white_control, move.position);
        // }
        // else {
        //     brd.setBit(&board.black_control, move.position);
        // }

        brd.clearBit(&board.empty_squares, move.position);

        switch (@as(brd.StoneType, @enumFromInt(move.flag))) {
            .Flat => {
                if (place_color == brd.Color.White) {
                    board.white_stones_remaining -= 1;
                } else {
                    board.black_stones_remaining -= 1;
                }
            },
            .Standing => {
                brd.setBit(&board.standing_stones, move.position);
                if (place_color == brd.Color.White) {
                    board.white_stones_remaining -= 1;
                } else {
                    board.black_stones_remaining -= 1;
                }
            },
            .Capstone => {
                brd.setBit(&board.capstones, move.position);
                if (place_color == brd.Color.White) {
                    board.white_capstones_remaining -= 1;
                } else {
                    board.black_capstones_remaining -= 1;
                }
            },
        }

        return;
    }

    // slide move
    const dir: brd.Direction = @enumFromInt(move.flag);
    const length: usize = @popCount(move.pattern);
    const end_pos: brd.Position = brd.nthPositionFrom(move.position, dir, length) orelse unreachable;

    // crush if needed
    if (board.squares[end_pos].top()) |stone| {
        if (stone.stone_type == brd.StoneType.Standing) {
            board.squares[end_pos].stack[board.squares[end_pos].len - 1].?.stone_type = brd.StoneType.Flat;
            board.crushMoves[board.half_move_count % brd.crush_map_size] = .Crush;
            // std.debug.print("Doing crush move\n", .{});
            did_crush = true;
        }
    }

    var started: bool = false;
    var cur_pos: brd.Position = move.position;
    var stones_moved: usize = 0;
    const count = move.movedStones();
    for (0..8) |i| {
        const bit = (move.pattern >> (7 - @as(u3, @intCast(i)))) & 0x1;
        if (!started) {
            if (bit == 1) {
                started = true;
            } else {
                continue;
            }
        }
        if (bit == 1) {
            cur_pos = brd.nextPosition(cur_pos, dir) orelse unreachable;
        }
        const stack_index = board.squares[move.position].len - count + stones_moved;
        const to_move: brd.Piece = board.squares[move.position].stack[stack_index].?;
        // board.squares[cur_pos].push(to_move);
        board.pushPieceToSquare(cur_pos, to_move);
        stones_moved += 1;
    }

    // board.squares[move.position].remove(move.movedStones()) catch unreachable;
    board.removePiecesFromSquare(move.position, stones_moved) catch unreachable;

    cur_pos = move.position;
}

pub fn checkUndoMove(board: brd.Board, move: brd.Move) MoveError!void {
    const color: brd.Color = board.to_move.opposite();

    if (!brd.isOnBoardPos(move.position)) {
        return MoveError.InvalidPosition;
    }

    if (move.pattern == 0) {
        if (board.squares[move.position].len != 1) {
            return MoveError.InvalidPosition;
        }

        const top_stone = board.squares[move.position].top() orelse return MoveError.InvalidStone;

        if (top_stone.color != color and board.half_move_count > 2) {
            return MoveError.InvalidColor;
        } 
        else if (top_stone.color == color and board.half_move_count <= 2) {
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
    
    var cur_pos = move.position;
    while (cur_pos != end_pos) {
        if (board.squares[cur_pos].top()) |stone| {
            if (stone.stone_type == brd.StoneType.Standing) {
                return MoveError.InvalidSlide;
            }
        }
        cur_pos = brd.nextPosition(cur_pos, dir) orelse return MoveError.InvalidPattern;
    }


    // Reconstruct the list of destination positions used during the original slide.
    var positions: [8]brd.Position = undefined;
    var idx: usize = 0;
    var started: bool = false;
    cur_pos= move.position;

    for (0..8) |i| {
        const bit = (move.pattern >> (7 - @as(u3, @intCast(i)))) & 0x1;

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
    std.debug.assert(board.half_move_count > 0);
    try checkUndoMove(board.*, move);
    undoMove(board, move);
}
pub fn undoMove(board: *brd.Board, move: brd.Move) void {
    defer {
        board.half_move_count -= 1;
        board.crushMoves[board.half_move_count % brd.crush_map_size] = .NoCrush;
    }

    if (move.pattern == 0) {
        zob.updateZobristHash(board, move);
        board.to_move = board.to_move.opposite();
        const top_stone = board.squares[move.position].top() orelse unreachable;
        const color = top_stone.color;

        const popped: brd.Piece = top_stone;
        board.removePiecesFromSquare(move.position, 1) catch unreachable;

        switch (popped.stone_type) {
            .Flat => {
                if (color == brd.Color.White) {
                    board.white_stones_remaining += 1;
                } else {
                    board.black_stones_remaining += 1;
                }
            },
            .Standing => {
                brd.clearBit(&board.standing_stones, move.position);
                if (color == brd.Color.White) {
                    board.white_stones_remaining += 1;
                } else {
                    board.black_stones_remaining += 1;
                }
            },
            .Capstone => {
                brd.clearBit(&board.capstones, move.position);
                if (color == brd.Color.White) {
                    board.white_capstones_remaining += 1;
                } else {
                    board.black_capstones_remaining += 1;
                }
            },
        }

        return;
    }


    // slide move
    board.to_move = board.to_move.opposite();
    const dir: brd.Direction = @enumFromInt(move.flag);

    const end_pos: brd.Position = brd.nthPositionFrom(move.position, dir, @popCount(move.pattern)) orelse unreachable;
    var cur_pos: brd.Position = end_pos;

    var piece_buffer: [8]brd.Piece = undefined;
    var piece_count: usize = 0;

    // iterate backwards through pattern
    for (0..8) |i| {

        if (cur_pos == move.position) {
            break;
        }

        const bit = (move.pattern >> @as(u3, @intCast(i))) & 0x1;

        const top_piece: brd.Piece = board.squares[cur_pos].stack[board.squares[cur_pos].len - 1] orelse unreachable;
        board.removePiecesFromSquare(cur_pos, 1) catch unreachable;
        piece_buffer[piece_count] = top_piece;
        piece_count += 1;

        if (bit == 1) {
            cur_pos = brd.previousPosition(cur_pos, dir) orelse unreachable;
        }
    }

    for (0..piece_count) |j| {
        board.pushPieceToSquare(move.position, piece_buffer[piece_count - 1 - j]);
    }

    if (board.crushMoves[board.half_move_count - 1 % brd.crush_map_size] == .Crush) {
        board.squares[end_pos].stack[board.squares[end_pos].len - 1].?.stone_type = brd.StoneType.Standing;
        board.standing_stones |= brd.getPositionBB(end_pos);
    }

    zob.updateZobristHash(board, move);
}

pub fn generateMoves(board: *const brd.Board, moves: *MoveList) !void {

    if (board.half_move_count < 2) {
        for (0..brd.board_size * brd.board_size) |pos| {
            if (brd.getBit(board.empty_squares, @as(u6, @intCast(pos)))) {
                // will always have at least this much capacity to start
                moves.appendUnsafe(brd.Move{
                    .position = @as(u6, @intCast(pos)),
                    .pattern = 0,
                    .flag = @intFromEnum(brd.StoneType.Flat),
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
        if (brd.getBit(board.empty_squares, @as(u6, @intCast(pos)))) {
            if (color == brd.Color.White) {
                if (board.white_stones_remaining > 0) {
                    moves.appendUnsafe(brd.Move{
                        .position = @as(u6, @intCast(pos)),
                        .pattern = 0,
                        .flag = @intFromEnum(brd.StoneType.Flat),
                    });
                    moves.appendUnsafe(brd.Move{
                        .position = @as(u6, @intCast(pos)),
                        .pattern = 0,
                        .flag = @intFromEnum(brd.StoneType.Standing),
                    });
                }
                if (board.white_capstones_remaining > 0) {
                    moves.appendUnsafe(brd.Move{
                        .position = @as(u6, @intCast(pos)),
                        .pattern = 0,
                        .flag = @intFromEnum(brd.StoneType.Capstone),
                    });
                }
            } else {
                if (board.black_stones_remaining > 0) {
                    moves.appendUnsafe(brd.Move{
                        .position = @as(u6, @intCast(pos)),
                        .pattern = 0,
                        .flag = @intFromEnum(brd.StoneType.Flat),
                    });
                    moves.appendUnsafe(brd.Move{
                        .position = @as(u6, @intCast(pos)),
                        .pattern = 0,
                        .flag = @intFromEnum(brd.StoneType.Standing),
                    });
                }
                if (board.black_capstones_remaining > 0) {
                    moves.appendUnsafe(brd.Move{
                        .position = @as(u6, @intCast(pos)),
                        .pattern = 0,
                        .flag = @intFromEnum(brd.StoneType.Capstone),
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
        if (!brd.getBit(color_bits, @as(u6, @intCast(pos)))) {
            continue;
        }
        var can_crush: bool = false;
        if (board.squares[pos].top()) |top_stone| {
            if (top_stone.stone_type == brd.StoneType.Capstone) {
                // std.debug.print("Can crush from position {d}\n", .{pos});
                can_crush = true;
            }
        }

        const max_pickup = if (board.squares[pos].len < brd.max_pickup) board.squares[pos].len else brd.max_pickup;

        const dirs: [4]brd.Direction = .{ .North, .South, .East, .West };

        for (dirs) |dir| {
            var max_steps = numSteps(board, @as(u6, @intCast(pos)), dir);
            if (max_steps > max_pickup) {
                max_steps = max_pickup;
            }

            var doing_crush: bool = false;

            // check if we can crush at the end
            if (can_crush and max_steps < brd.max_pickup) {
                // std.debug.print("Checking crush move from pos {d} in dir {} with max_steps {d}\n", .{pos, dir, max_steps});
                if (brd.nthPositionFrom(@as(u6, @intCast(pos)), dir, max_steps + 1)) |end_pos| {
                    if (board.squares[end_pos].top()) |stone| {
                        if (stone.stone_type == brd.StoneType.Standing) {
                            // std.debug.print("Can do crush move from pos {d} to {d} in dir {}\n", .{pos, end_pos, dir});
                            doing_crush = true;
                        }
                    }
                }
            }

            if (max_steps != 0) {
                const patterns = sym.patterns.patterns[max_pickup - 1][max_steps - 1];

                if (moves.count + patterns.len > moves.capacity) {
                    try moves.resize(moves.capacity * 2);
                }
                for (0..patterns.len) |pattern| {
                    moves.appendUnsafe(brd.Move{
                        .position = @as(u6, @intCast(pos)),
                        .pattern = patterns.items[pattern],
                        .flag = @intFromEnum(dir),
                    });
                }
            }

            if (doing_crush) {
                const crush_patterns = sym.patterns.crush_patterns[max_pickup - 1][max_steps];
                if (moves.count + crush_patterns.len > moves.capacity) {
                    try moves.resize(moves.capacity * 2);
                }

                for (0..crush_patterns.len) |pattern| {
                    moves.appendUnsafe(brd.Move{
                        .position = @as(u6, @intCast(pos)),
                        .pattern = crush_patterns.items[pattern],
                        .flag = @intFromEnum(dir),
                    });
                }
            }
        }
    }
}

pub fn numSteps(board: *const brd.Board, start: brd.Position, dir: brd.Direction) usize {
    var steps: usize = 0;
    var cur_pos = brd.nextPosition(start, dir) orelse return steps;

    for (0..brd.max_pickup) |_| {
        if ((board.standing_stones | board.capstones) & brd.getPositionBB(cur_pos) != 0) {
            return steps;
        }
        steps += 1;
        cur_pos = brd.nextPosition(cur_pos, dir) orelse return steps;
    }
    return steps;
}

pub fn countMoves(board: *const brd.Board) !usize {

    if (board.half_move_count < 2) {
        return @as(usize, @intCast(@popCount(board.empty_squares)));
    }

    var total: usize = 0;
    total += try countPlaceMoves(board);
    total += try countSlideMoves(board);
    return total;
}

fn countPlaceMoves(board: *const brd.Board) !usize {
    const color: brd.Color = board.to_move;
    const stones = if (color == brd.Color.White) board.white_stones_remaining else board.black_stones_remaining;
    const capstones = if (color == brd.Color.White) board.white_capstones_remaining else board.black_capstones_remaining;

    var total: usize = 0;
    if (stones > 0) {
        total += @as(usize, @intCast(@popCount(board.empty_squares) * 2));
    }
    if (capstones > 0) {
        total += @as(usize, @intCast(@popCount(board.empty_squares)));
    }
    return total;
}

fn countSlideMoves(board: *const brd.Board) !usize {
    const color: brd.Color = board.to_move;
    const color_bits = if (color == brd.Color.White) board.white_control else board.black_control;

    var total: usize = 0;

    for (0..brd.board_size * brd.board_size) |pos| {
        if (!brd.getBit(color_bits, @as(u6, @intCast(pos)))) {
            continue;
        }
        var can_crush: bool = false;
        if (board.squares[pos].top()) |top_stone| {
            if (top_stone.stone_type == brd.StoneType.Capstone) {
                can_crush = true;
            }
        }

        const max_pickup = if (board.squares[pos].len < brd.max_pickup) board.squares[pos].len else brd.max_pickup;

        const dirs: [4]brd.Direction = .{ .North, .South, .East, .West };

        for (dirs) |dir| {
            var max_steps = numSteps(board, @as(u6, @intCast(pos)), dir);
            if (max_steps > max_pickup) {
                max_steps = max_pickup;
            }

            var doing_crush: bool = false;

            // check if we can crush at the end
            if (can_crush and max_steps < brd.max_pickup) {
                // std.debug.print("Checking crush move from pos {d} in dir {} with max_steps {d}\n", .{pos, dir, max_steps});
                if (brd.nthPositionFrom(@as(u6, @intCast(pos)), dir, max_steps + 1)) |end_pos| {
                    if (board.squares[end_pos].top()) |stone| {
                        if (stone.stone_type == brd.StoneType.Standing) {
                            // std.debug.print("Can do crush move from pos {d} to {d} in dir {}\n", .{pos, end_pos, dir});
                            doing_crush = true;
                        }
                    }
                }
            }

            if (max_steps != 0) {
                const patterns = sym.patterns.patterns[max_pickup - 1][max_steps - 1];

                total += patterns.len;
            }

            if (doing_crush) {
                const crush_patterns = sym.patterns.crush_patterns[max_pickup - 1][max_steps];
                total += crush_patterns.len;
            }
        }
    }
    return total;
}
