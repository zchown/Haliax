const std = @import("std");
const zob = @import("zobrist");
const road = @import("road");
const tracy = @import("tracy");
const tracy_enable = tracy.build_options.enable_tracy;

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

// whether to use union-find for road detection
// alternative is flood fill bitboard method
// slower for 6x6 might be faster for 8x8 needs 
// benchmarking
pub const do_road_uf = false;

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

    pub inline fn top(self: *const Square) ?Piece {
        if (self.len == 0) return null;
        return self.stack[self.len - 1];
    }

    pub inline fn pushPiece(self: *Square, piece: Piece) void {
        self.stack[self.len] = piece;
        self.len += 1;
        switch (piece.color) {
            .White => self.white_count += 1,
            .Black => self.black_count += 1,
        }
    }

    pub inline fn removePieces(self: *Square, count: usize) !void {
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
    pub inline fn movedStones(self: Move) usize {
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

    white_stones_remaining: usize,
    black_stones_remaining: usize,

    white_capstones_remaining: usize,
    black_capstones_remaining: usize,

    zobrist_hash: zob.ZobristHash,

    to_move: Color,
    half_move_count: usize,

    white_control: Bitboard,
    black_control: Bitboard,
    empty_squares: Bitboard,
    standing_stones: Bitboard,
    capstones: Bitboard,

    crushMoves: [crush_map_size]Crush,

    game_status: Result,

    white_road_uf: road.RoadUF,
    black_road_uf: road.RoadUF,
    road_dirty_white: bool,
    road_dirty_black: bool,
    supress_road_incremental: bool,

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
            .white_road_uf = road.RoadUF.init(),
            .black_road_uf = road.RoadUF.init(),
            .road_dirty_white = false,
            .road_dirty_black = false,
            .supress_road_incremental = false,
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
        self.white_road_uf.clear();
        self.black_road_uf.clear();
        self.road_dirty_white = false;
        self.road_dirty_black = false;
        self.supress_road_incremental = false;
        zob.computeZobristHash(self);
    }

    pub fn equals(self: *const Board, other: *const Board) bool {
        return self.zobrist_hash == other.zobrist_hash;
    }

    pub fn checkResult(self: *Board) Result {
        if (tracy_enable) {
            const z = tracy.trace(@src());
            defer z.end();
        }
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
            if (do_road_uf) {
                self.checkRoadWinUF();
            } else {
                self.checkRoadWin();
            }
        }
    }

    fn checkRoadWinUF(self: *Board) void {
        if (tracy_enable) {
            const z = tracy.trace(@src());
            defer z.end();
        }

        const current: Color = self.to_move.opposite();
        const opponent: Color = self.to_move;

        if (self.hasRoadUF(current)) {
            self.game_status = Result{
                .road = 1,
                .flat = 0,
                .color = if (current == .White) 0 else 1,
                .ongoing = 0,
            };
            return;
        }

        if (self.hasRoadUF(opponent)) {
            self.game_status = Result{
                .road = 1,
                .flat = 0,
                .color = if (opponent == .White) 0 else 1,
                .ongoing = 0,
            };
            return;
        }

        self.game_status = Result{ .road = 0, .flat = 0, .color = 0, .ongoing = 1 };
    }

    fn checkRoadWin(self: *Board) void {
        if (tracy_enable) {
            const z = tracy.trace(@src());
            defer z.end();
        }

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

            self.game_status = Result{
                .road = 0,
                .flat = 0,
                .color = 0,
                .ongoing = 1,
            };
    }

    fn hasRoad(player_controlled: Bitboard, search_dir: SearchDirection) bool {
        if (tracy_enable) {
            const z = tracy.trace(@src());
            defer z.end();
        }

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

    pub inline fn isSquareEmpty(self: *const Board, pos: Position) bool {
        return getBit(self.empty_squares, pos);
    }

    pub inline fn recomputeHash(self: *Board) void {
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

        self.road_dirty_white = true;
        self.road_dirty_black = true;
    }

    fn roadMaskForColor(self: *Board, color: Color) Bitboard {
        var controlled: Bitboard = 0;
        if (color == .White) {
            controlled = self.white_control;
        }
        else {
            controlled = self.black_control;
        }
        return controlled & ~self.standing_stones;
    }

    fn ensureRoadUpToDate(self: *Board, color: Color) void {
        if (color == .White) {
            if (!self.road_dirty_white) return;
            const road_mask = self.roadMaskForColor(.White);
            self.white_road_uf.rebuildFromMask(road_mask);
            self.road_dirty_white = false;
        }
        else {
            if (!self.road_dirty_black) return;
            const road_mask = self.roadMaskForColor(.Black);
            self.black_road_uf.rebuildFromMask(road_mask);
            self.road_dirty_black = false;
        }
    }

    inline fn markRoadDirty(self: *Board, color: Color) void {
        if (color == .White) {
            self.road_dirty_white = true;
        } else {
            self.road_dirty_black = true;
        }
    }

    inline fn isRoadTopPiece(piece: ?Piece) bool {
        if (piece == null) return false;
        return piece.?.stone_type != .Standing;
    }

    inline fn roadTopColor(piece: ?Piece) ?Color {
        if (piece == null) return null;
        if (piece.?.stone_type == .Standing) return null;
        return piece.?.color;
    }

    pub fn onTopPieceChanged(self: *Board, pos: Position, old_piece: ?Piece, new_piece: ?Piece) void {
        const old_color = roadTopColor(old_piece);
        const new_color = roadTopColor(new_piece);

        if (old_color == new_color) return;

        if (self.supress_road_incremental) {
            if (old_color) |color| {
                self.markRoadDirty(color);
            }
            if (new_color) |color| {
                self.markRoadDirty(color);
            }
            return;
        }

        if (old_color == null and new_color != null) {
            const color = new_color.?;
            self.ensureRoadUpToDate(color);
            const mask = self.roadMaskForColor(color);
            if (color == .White) {
                self.white_road_uf.addPosIncremental(pos, mask);
            } else {
                self.black_road_uf.addPosIncremental(pos, mask);
            }
            return;
        }

        if (old_color) |color| {
            self.markRoadDirty(color);
        }
        if (new_color) |color| {
            self.markRoadDirty(color);
        }
    }

    fn hasRoadUF(self: *Board, color: Color) bool {
        self.ensureRoadUpToDate(color);
        if (color == .White) {
            return self.white_road_uf.has_road_h or self.white_road_uf.has_road_v;
        } else {
            return self.black_road_uf.has_road_h or self.black_road_uf.has_road_v;
        }
    }

    pub fn pushPieceToSquareNoUpdate(self: *Board, pos: Position, piece: Piece) void {
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

    pub fn pushPieceToSquare(self: *Board, pos: Position, piece: Piece) void {
        var old_top_piece: ?Piece = null;

        if (do_road_uf) {
            old_top_piece = self.squares[pos].top();
        }

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

        if (do_road_uf) {
            self.onTopPieceChanged(pos, old_top_piece, self.squares[pos].top());
        }
    }

    pub fn removePiecesFromSquareNoUpdate(self: *Board, pos: Position, count: usize) !void {
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

    pub fn removePiecesFromSquare(self: *Board, pos: Position, count: usize) !void {
        const square = &self.squares[pos];
        var old_top_piece: ?Piece = null;

        if (do_road_uf) {
            old_top_piece = square.top();
        }

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
        if (!do_road_uf) {
            self.onTopPieceChanged(pos, old_top_piece, square.top());
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
    return pos < @as(Position, num_squares);
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

pub inline fn nextPosition(pos: Position, dir: Direction) ?Position {
    const bs: Position = @as(Position, board_size);
    switch (dir) {
        .North => return if (pos + bs < @as(Position, num_squares)) pos + bs else null,
        .South => return if (pos >= bs) pos - bs else null,
        .East  => {
            const x: Position = pos % bs;
            return if (x + 1 < bs) pos + 1 else null;
        },
        .West  => {
            const x: Position = pos % bs;
            return if (x != 0) pos - 1 else null;
        },
    }
}

pub fn previousPosition(pos: Position, dir: Direction) ?Position {
    return nextPosition(pos, opositeDirection(dir));
}

pub fn nthPositionFrom(pos: Position, dir: Direction, n: usize) ?Position {
    const bs_u: usize = board_size;
    const pos_u: usize = @intCast(pos);

    switch (dir) {
        .North => {
            const step = n * bs_u;
            const new_u = pos_u + step;
            return if (new_u < num_squares) @as(Position, @intCast(new_u)) else null;
        },
        .South => {
            const step = n * bs_u;
            return if (pos_u >= step) @as(Position, @intCast(pos_u - step)) else null;
        },
        .East => {
            const x = pos_u % bs_u;
            return if (x + n < bs_u) @as(Position, @intCast(pos_u + n)) else null;
        },
        .West => {
            const x = pos_u % bs_u;
            return if (n <= x) @as(Position, @intCast(pos_u - n)) else null;
        },
    }
}

pub fn bbGetNthPositionFrom(bb: Bitboard, dir: Direction, n: usize) Bitboard {
    var result: Bitboard = bb;

    for (0..n) |_| {
        result = switch (dir) {
            .North => (result << board_size) & board_mask,
            .South => (result >> board_size) & board_mask,
            .East => (result << 1) & board_mask & ~column_masks[0],
            .West => (result >> 1) & board_mask & ~column_masks[board_size - 1],
        };
    }
    return result;
}

pub fn printBB(bb: Bitboard) void {
    std.debug.print("Bitboard:\n", .{});
    for (0..board_size) |row| {
        for (0..board_size) |col| {
            const pos: Position = getPos(col, @as(usize, row));
            const occupied = getBit(bb, pos);
            _ = std.debug.print("{s} ", .{if (occupied) "#" else "."});
        }
        _ = std.debug.print("\n", .{});
    }
}
