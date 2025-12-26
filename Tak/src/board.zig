const std = @import("std");
const zob = @import("zobrist");

pub const board_size = 6;
pub const num_squares = board_size * board_size;
pub const stone_count = 30;
pub const capstone_count = 1;
pub const total_pieces = stone_count + capstone_count;
pub const max_pickup = board_size;
pub const max_stack_height = 2 * stone_count + 1;
pub const komi = 2.0;
pub const num_piece_types = 3;
pub const num_colors = 2;
pub const zobrist_stack_depth = board_size + 1;
pub const num_directions = 4;
pub const crush_map_size = 256;

pub const StoneType = enum(u2) {
    Flat,
    Standing,
    Capstone,
};

pub const Color = enum(u1) {
    White = 0,
    Black = 1,

    pub fn opposite(self: Color) Color {
        return switch (self) {
            .White => .Black,
            .Black => .White,
        };
    }
};

pub const Position = u6;
pub const Bitboard = u64;

pub inline fn setBit(bb: *Bitboard, pos: Position) void {
    bb.* |= (getPositionBB(pos));
}

pub inline fn clearBit(bb: *Bitboard, pos: Position) void {
    bb.* &= ~(getPositionBB(pos));
}

pub inline fn getBit(bb: Bitboard, pos: Position) bool {
    return (bb & getPositionBB(pos)) != 0;
}

pub inline fn countBits(bb: Bitboard) u32 {
    return @popCount(bb);
}

pub inline fn getLSB(bb: Bitboard) Position {
    return @ctz(bb);
}

pub inline fn getPositionBB(pos: Position) Bitboard {
    return (@as(Bitboard, 1) << pos);
}

pub inline fn popBit(bb: Bitboard, pos: Position) void {
    if (getBit(bb, pos)) {
        bb.* ^= getPositionBB(pos);
    }
}

pub fn printBitboard(bb: Bitboard) void {
    const stdout = std.io.getStdOut().writer();
    for (0..board_size) |row| {
        for (0..board_size) |col| {
            const pos: u6 = @intCast(row * board_size + col);
            const occupied = (bb & (@as(Bitboard, 1) << pos)) != 0;
            _ = stdout.print("{s} ", .{if (occupied) "#" else "."});
        }
        _ = stdout.print("\n", .{});
    }
}

pub const board_mask = generateBoardMask();
fn generateBoardMask() Bitboard {
    if (board_size * board_size > @bitSizeOf(Bitboard)) {
        @compileError("Board does not fit into Bitboard");
    }
    var mask: Bitboard = 0;
    for (0..board_size * board_size) |pos| {
        mask |= (@as(Bitboard, 1) << @intCast(pos));
    }
    return mask;
}

pub const column_masks: [board_size]Bitboard = generateColumnMasks();
fn generateColumnMasks() [board_size]Bitboard {
    if (board_size * board_size > @bitSizeOf(Bitboard)) {
        @compileError("Board does not fit into Bitboard");
    }
    var masks: [board_size]Bitboard = undefined;

    for (0..board_size) |col| {
        var mask: Bitboard = 0;

        for (0..board_size) |row| {
            const pos: u6 = @intCast(row * board_size + col);
            mask |= (@as(Bitboard, 1) << pos);
        }

        masks[col] = mask;
    }

    return masks;
}

pub const row_masks: [board_size]Bitboard = generateRowMasks();
fn generateRowMasks() [board_size]Bitboard {
    if (board_size * board_size > @bitSizeOf(Bitboard)) {
        @compileError("Board does not fit into Bitboard");
    }
    var masks: [board_size]Bitboard = undefined;
    for (0..board_size) |row| {
        var mask: Bitboard = 0;

        for (0..board_size) |col| {
            const pos: u6 = @intCast(row * board_size + col);
            mask |= (@as(Bitboard, 1) << pos);
        }

        masks[row] = mask;
    }
    return masks;
}

pub const Direction = enum(u2) {
    North,
    South,
    East,
    West,
};

pub const Piece = packed struct(u4) {
    stone_type: StoneType,
    color: Color,
    _padding: u1 = 0,
};

pub const PieceStack = struct {
    pieces: [max_pickup]?Piece,
    len: usize,
};

pub const Square = struct {
    stack: [max_stack_height]?Piece,
    len: usize,
    white_count: usize,
    black_count: usize,

    pub fn init() Square {
        return Square{
            .stack = [_]?Piece{null} ** max_stack_height,
            .len = 0,
            .white_count = 0,
            .black_count = 0,
        };
    }

    pub fn top(self: *const Square) ?Piece {
        if (self.len == 0) return null;
        return self.stack[self.len - 1];
    }

    pub fn pushPiece(self: *Square, piece: Piece) void {
        self.stack[self.len] = piece;
        self.len += 1;
        switch (piece.color) {
            .White => self.white_count += 1,
            .Black => self.black_count += 1,
        }
    }

    pub fn removePieces(self: *Square, count: usize) !void {
        if (count > self.len) {
            return error.StackUnderflow;
        }
        for (0..count) |i| {
            const piece = self.stack[self.len - count + i];
            switch (piece.?.color) {
                .White => self.white_count -= 1,
                .Black => self.black_count -= 1,
            }
            self.stack[self.len - count + i] = null;
        }
        self.len -= count;
    }
};

pub const Result = packed struct(u4) {
    road: u1, // 1 if a player has formed a road
    flat: u1, // 1 if a flat win has occurred
    color: u1, // which color won
    ongoing: u1, // 1 if the game is still ongoing
    // all 0 if draw
};

pub const Crush = enum(u1) {
    NoCrush,
    Crush,
};

pub const MoveType = enum(u1) {
    Place,
    Slide,
};

pub const Move = packed struct(u16) {
    position: Position,
    flag: u2, // either direction or stone type
    // 0 for drop, 1 for move and drop
    pattern: u8, // only for Slide, 0b00000000 for Place

    pub inline fn createPlaceMove(pos: Position, stone_type: StoneType) Move {
        return Move{
            .position = pos,
            .flag = @intFromEnum(stone_type),
            .pattern = 0,
        };
    }

    pub inline fn createSlideMove(pos: Position, direction: Direction, pattern: u8) Move {
        return Move{
            .position = pos,
            .flag = @intFromEnum(direction),
            .pattern = pattern,
        };
    }

    pub fn print(self: Move) void {
        if (self.pattern == 0) {
            const stone_type = switch (@as(StoneType, @enumFromInt(self.flag))) {
                .Flat => "Flat",
                .Standing => "Standing",
                .Capstone => "Capstone",
            };
            std.debug.print("Place {s} at ({d}, {d})\n", .{ stone_type, getX(self.position), getY(self.position) });
        } else {
            const direction = switch (@as(Direction, @enumFromInt(self.flag))) {
                .North => "North",
                .South => "South",
                .East => "East",
                .West => "West",
            };
            std.debug.print("Slide from ({d}, {d}) to {s} with pattern {b}\n", .{ getX(self.position), getY(self.position), direction, self.pattern });
        }
    }

    // position of most significant bit in pattern
    pub fn movedStones(self: Move) usize {
        return 8 - @clz(self.pattern);
    }
};

pub fn movesEqual(a: Move, b: Move) bool {
    return a.position == b.position and
        a.flag == b.flag and
        a.pattern == b.pattern;
}

const SearchDirection = enum {
    Vertical,
    Horizontal,
};

pub const Board = struct {
    squares: [num_squares]Square,
    white_stones_remaining: usize = stone_count,
    black_stones_remaining: usize = stone_count,
    white_capstones_remaining: usize = capstone_count,
    black_capstones_remaining: usize = capstone_count,
    zobrist_hash: zob.ZobristHash = 0,
    to_move: Color = .White,
    half_move_count: usize = 0,
    white_control: Bitboard = 0,
    black_control: Bitboard = 0,
    empty_squares: Bitboard = 0,
    standing_stones: Bitboard = 0,
    capstones: Bitboard = 0,
    crushMoves: [crush_map_size]Crush = undefined,
    game_status: Result = Result{
        .road = 0,
        .flat = 0,
        .color = 0,
        .ongoing = 1,
    },

    pub fn init() Board {
        var brd = Board{
            .squares = [_]Square{Square.init()} ** 36,
            .white_stones_remaining = stone_count,
            .black_stones_remaining = stone_count,
            .white_capstones_remaining = capstone_count,
            .black_capstones_remaining = capstone_count,
            .zobrist_hash = 0,
            .to_move = .White,
            .half_move_count = 0,
            .white_control = 0,
            .black_control = 0,
            .empty_squares = board_mask,
            .standing_stones = 0,
            .capstones = 0,
            .crushMoves = [_]Crush{.NoCrush} ** crush_map_size,
            .game_status = Result{
                .road = 0,
                .flat = 0,
                .color = 0,
                .ongoing = 1,
            },
        };

        zob.computeZobristHash(&brd);
        return brd;
    }

    pub fn reset(self: *Board) !void {
        self.squares = [_]Square{} ** num_squares;
        self.white_stones_remaining = stone_count;
        self.black_stones_remaining = stone_count;
        self.white_capstones_remaining = capstone_count;
        self.black_capstones_remaining = capstone_count;
        self.zobrist_hash = 0;
        self.to_move = .White;
        self.half_move_count = 0;
        self.white_control = 0;
        self.black_control = 0;
        self.empty_squares = board_mask;
        self.standing_stones = 0;
        self.capstones = 0;
        self.game_status = Result{
            .road = 0,
            .flat = 0,
            .color = 0,
            .ongoing = 1,
        };
        try self.gameHistory.clear();
        zob.computeZobristHash(self);
    }

    pub fn equals(self: *const Board, other: *const Board) bool {
        return self.zobrist_hash == other.zobrist_hash;
    }

    pub fn checkResult(self: *Board) Result {
        self.updateResult();
        return self.game_status;
    }

    fn updateResult(self: *Board) void {
        if (self.empty_squares == 0) {
            const white_flats: Bitboard = (self.white_control & ~self.standing_stones) & ~self.capstones;
            const black_flats: Bitboard = (self.black_control & ~self.standing_stones) & ~self.capstones;
            const white_count: f64 = @as(f64, @floatFromInt(countBits(white_flats)));
            const black_count: f64 = @as(f64, @floatFromInt(countBits(black_flats)));
            if (white_count == black_count + komi) {
                self.game_status = Result{
                    .road = 0,
                    .flat = 0,
                    .color = 0,
                    .ongoing = 0,
                };
            } else if (black_count + komi > white_count) {
                self.game_status = Result{
                    .road = 0,
                    .flat = 1,
                    .color = 1,
                    .ongoing = 0,
                };
            } else {
                self.game_status = Result{
                    .road = 0,
                    .flat = 1,
                    .color = 0,
                    .ongoing = 0,
                };
            }
        } else {
            self.checkRoadWin();
        }
    }

    fn checkRoadWin(self: *Board) void {
        const current: Color = self.to_move.opposite();
        const opponent: Color = self.to_move;

        const current_controlled = if (current == .White)
            (self.white_control & ~self.standing_stones)
        else
            (self.black_control & ~self.standing_stones);

        const opponent_controlled = if (opponent == .White)
            (self.white_control & ~self.standing_stones)
        else
            (self.black_control & ~self.standing_stones);

        if (hasRoad(current_controlled, .Vertical) or hasRoad(current_controlled, .Horizontal)) {
            self.game_status = Result{
                .road = 1,
                .flat = 0,
                .color = if (current == .White) 0 else 1,
                .ongoing = 0,
            };
            return;
        }

        if (hasRoad(opponent_controlled, .Vertical) or hasRoad(opponent_controlled, .Horizontal)) {
            self.game_status = Result{
                .road = 1,
                .flat = 0,
                .color = if (opponent == .White) 0 else 1,
                .ongoing = 0,
            };
            return;
        }
    }

    pub fn isSquareEmpty(self: *const Board, pos: Position) bool {
        return self.squares[pos].len == 0;
    }

    pub fn recomputeHash(self: *Board) void {
        zob.computeZobristHash(self);
    }

    pub fn recomputeBitboards(self: *Board) void {
        self.white_control = 0;
        self.black_control = 0;
        self.empty_squares = 0;
        self.standing_stones = 0;
        self.capstones = 0;

        for (0..num_squares) |pos| {
            const sq = &self.squares[pos];

            if (sq.len == 0) {
                setBit(&self.empty_squares, @intCast(pos));
            } else {
                const top_piece = sq.top().?;

                if (top_piece.color == .White) {
                    setBit(&self.white_control, @intCast(pos));
                } else {
                    setBit(&self.black_control, @intCast(pos));
                }

                if (top_piece.stone_type == .Standing) {
                    setBit(&self.standing_stones, @intCast(pos));
                } else if (top_piece.stone_type == .Capstone) {
                    setBit(&self.capstones, @intCast(pos));
                }
            }
        }
    }

    pub fn pushPieceToSquare(self: *Board, pos: Position, piece: Piece) void {
        self.squares[pos].pushPiece(piece);
        // update bitboards
        clearBit(&self.empty_squares, pos);
        clearBit(&self.standing_stones, pos);
        clearBit(&self.capstones, pos);
        clearBit(&self.white_control, pos);
        clearBit(&self.black_control, pos);
        if (piece.stone_type == .Standing) {
            setBit(&self.standing_stones, pos);
        } else if (piece.stone_type == .Capstone) {
            setBit(&self.capstones, pos);
        }
        if (piece.color == .White) {
            setBit(&self.white_control, pos);
        } else {
            setBit(&self.black_control, pos);
        }
    }

    pub fn removePiecesFromSquare(self: *Board, pos: Position, count: usize) !void {
        const square = &self.squares[pos];

        clearBit(&self.white_control, pos);
        clearBit(&self.black_control, pos);
        clearBit(&self.standing_stones, pos);
        clearBit(&self.capstones, pos);

        try square.removePieces(count);
        if (square.len == 0) {
            setBit(&self.empty_squares, pos);
        } else {
            const top_piece = square.top().?;
            if (top_piece.stone_type == .Standing) {
                setBit(&self.standing_stones, pos);
            } else if (top_piece.stone_type == .Capstone) {
                setBit(&self.capstones, pos);
            }
            if (top_piece.color == .White) {
                setBit(&self.white_control, pos);
            } else {
                setBit(&self.black_control, pos);
            }
        }
    }
};

pub inline fn getPos(x: usize, y: usize) Position {
    return @intCast(y * board_size + x);
}

pub inline fn getX(pos: Position) usize {
    return @as(usize, @intCast(pos)) % board_size;
}

pub inline fn getY(pos: Position) usize {
    return @as(usize, @intCast(pos)) / board_size;
}

pub inline fn isOnBoard(x: isize, y: isize) bool {
    return x >= 0 and x < @as(isize, board_size) and y >= 0 and y < @as(isize, board_size);
}

pub inline fn isOnBoardPos(pos: Position) bool {
    const x = @as(isize, @intCast(getX(pos)));
    const y = @as(isize, @intCast(getY(pos)));
    return isOnBoard(x, y);
}

pub inline fn directionOffset(dir: Direction) isize {
    return switch (dir) {
        .North => @as(isize, board_size),
        .South => -@as(isize, board_size),
        .East => 1,
        .West => -1,
    };
}

pub inline fn opositeDirection(dir: Direction) Direction {
    return switch (dir) {
        .North => .South,
        .South => .North,
        .East => .West,
        .West => .East,
    };
}

pub fn nextPosition(pos: Position, dir: Direction) ?Position {
    const x = @as(isize, @intCast(getX(pos)));
    const y = @as(isize, @intCast(getY(pos)));
    const offset = directionOffset(dir);
    const new_x = x + (if (dir == .East or dir == .West) offset else 0);
    const new_y = y + (if (dir == .North or dir == .South) @divTrunc(offset, @as(isize, board_size)) else 0);
    if (isOnBoard(new_x, new_y)) {
        return getPos(@as(usize, @intCast((new_x))), @as(usize, @intCast(new_y)));
    } else {
        return null;
    }
}

pub fn previousPosition(pos: Position, dir: Direction) ?Position {
    return nextPosition(pos, opositeDirection(dir));
}

pub fn nthPositionFrom(pos: Position, dir: Direction, n: usize) ?Position {
    var current_pos: Position = pos;
    for (0..n) |_| {
        const next_pos = nextPosition(current_pos, dir);
        if (next_pos == null) {
            return null;
        }
        current_pos = next_pos.?;
    }
    return current_pos;
}

fn hasRoad(player_controlled: Bitboard, search_dir: SearchDirection) bool {
    const start_mask: Bitboard = if (search_dir == .Vertical) row_masks[board_size - 1] else column_masks[0];
    const end_mask: Bitboard = if (search_dir == .Vertical) row_masks[0] else column_masks[board_size - 1];

    if (search_dir == .Vertical) {
        for (row_masks) |mask| {
            if ((player_controlled & mask) == 0) return false;
        }
    } else {
        for (column_masks) |mask| {
            if ((player_controlled & mask) == 0) return false;
        }
    }

    var reachable: Bitboard = player_controlled & start_mask;
    if (reachable == 0) return false;

    var previous: Bitboard = 0;
    while (reachable != previous) {
        previous = reachable;

        const shifted_left = ((reachable & ~column_masks[board_size - 1]) << 1) & player_controlled;
        const shifted_right = ((reachable & ~column_masks[0]) >> 1) & player_controlled;
        const shifted_up = ((reachable & ~row_masks[board_size - 1]) << board_size) & player_controlled;
        const shifted_down = ((reachable & ~row_masks[0]) >> board_size) & player_controlled;

        reachable |= shifted_left | shifted_right | shifted_up | shifted_down;

        if ((reachable & end_mask) != 0) {
            return true;
        }
    }

    return false;
}
