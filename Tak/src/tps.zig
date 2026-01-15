const std = @import("std");
const brd = @import("board");

const Board = brd.Board;
const Square = brd.Square;
const Piece = brd.Piece;
const Color = brd.Color;
const StoneType = brd.StoneType;
const Position = brd.Position;
const tracy = @import("tracy");

const board_size = brd.board_size;

pub const TPSError = error{
    InvalidFormat,
    InvalidRowCount,
    InvalidColumnCount,
    InvalidPieceIndicator,
    OutOfMemory,
};

pub fn parseTPS(tps: []const u8) !Board {
    const z = tracy.trace(@src());
    defer z.end();

    var b = Board.init();

    var tps_str = tps;
    if (std.mem.startsWith(u8, tps, "[TPS ")) {
        tps_str = tps[5..];
    }

    // Split into three parts: board, turn, move number
    var parts = std.mem.splitScalar(u8, tps_str, ' ');

    const board_str = parts.next() orelse return TPSError.InvalidFormat;
    const turn_str = parts.next() orelse return TPSError.InvalidFormat;
    var move_str = parts.next() orelse return TPSError.InvalidFormat;

    if (move_str[move_str.len - 1] == ']') {
        move_str = move_str[0 .. move_str.len - 1];
    }

    // Parse turn
    b.to_move = if (turn_str[0] == '1') Color.White else Color.Black;

    // Parse move number
    b.half_move_count = try std.fmt.parseInt(usize, move_str, 10);
    b.half_move_count -= 1; // Convert to zero-based

    // Parse board string (rows separated by '/')
    var row_iter = std.mem.splitScalar(u8, board_str, '/');
    var row_count: usize = 0;

    while (row_iter.next()) |row_str| : (row_count += 1) {
        if (row_count >= board_size) {
            return TPSError.InvalidRowCount;
        }

        try parseRow(&b, row_str, row_count);
    }

    if (row_count != board_size) {
        return TPSError.InvalidRowCount;
    }

    try updateBoardState(&b);
    b.recomputeHash();
    b.updateAllVectors();

    return b;
}

fn parseRow(b: *Board, row_str: []const u8, row_num: usize) !void {
    const z = tracy.trace(@src());
    defer z.end();

    var col_iter = std.mem.splitScalar(u8, row_str, ',');
    var col_number: usize = 0;

    while (col_iter.next()) |token| {
        if (col_number >= board_size) {
            return TPSError.InvalidColumnCount;
        }

        if (token[0] == 'x') {
            var count: usize = 1;
            if (token.len > 1) {
                count = try std.fmt.parseInt(usize, token[1..], 10);
            }
            if (count == 0 or count > board_size) {
                count = 1;
            }
            col_number += count;
        } else {
            const pos = brd.getPos(col_number, (board_size - 1) - row_num);
            try parseStack(b, pos, token);
            col_number += 1;
        }
    }

    if (col_number != board_size) {
        return TPSError.InvalidColumnCount;
    }
}

fn parseStack(b: *Board, pos: Position, token: []const u8) !void {
    const z = tracy.trace(@src());
    defer z.end();

    var sq = &b.squares[pos];
    var i: usize = 0;

    while (i < token.len) {
        if (token[i] != '1' and token[i] != '2') {
            return TPSError.InvalidPieceIndicator;
        }

        const color: Color = if (token[i] == '1') .White else .Black;
        i += 1;

        var stone_type: StoneType = .Flat;
        if (i < token.len) {
            if (token[i] == 'S') {
                stone_type = .Standing;
                i += 1;
            } else if (token[i] == 'C') {
                stone_type = .Capstone;
                i += 1;
            }
        }

        const piece = Piece{
            .stone_type = stone_type,
            .color = color,
            ._padding = 0,
        };

        sq.pushPiece(piece);
    }
}

fn updateBoardState(b: *Board) !void {
    const z = tracy.trace(@src());
    defer z.end();

    b.white_control = 0;
    b.black_control = 0;
    b.empty_squares = 0;
    b.standing_stones = 0;
    b.capstones = 0;

    var white_stones: usize = brd.stone_count;
    var black_stones: usize = brd.stone_count;
    var white_caps: usize = brd.capstone_count;
    var black_caps: usize = brd.capstone_count;

    for (0..brd.num_squares) |pos| {
        const sq = &b.squares[pos];
        const pos_u6: u6 = @intCast(pos);

        if (sq.len == 0) {
            brd.setBit(&b.empty_squares, pos_u6);
        } else {
            const top_piece = sq.top().?;

            if (top_piece.color == .White) {
                brd.setBit(&b.white_control, pos_u6);
            } else {
                brd.setBit(&b.black_control, pos_u6);
            }

            if (top_piece.stone_type == .Standing) {
                brd.setBit(&b.standing_stones, pos_u6);
            } else if (top_piece.stone_type == .Capstone) {
                brd.setBit(&b.capstones, pos_u6);
            }

            for (0..sq.len) |i| {
                const piece = sq.stack[i].?;
                if (piece.color == .White) {
                    if (piece.stone_type == .Capstone) {
                        white_caps -|= 1;
                    } else {
                        white_stones -|= 1;
                    }
                } else {
                    if (piece.stone_type == .Capstone) {
                        black_caps -|= 1;
                    } else {
                        black_stones -|= 1;
                    }
                }
            }
        }
    }

    b.white_stones_remaining = white_stones;
    b.black_stones_remaining = black_stones;
    b.white_capstones_remaining = white_caps;
    b.black_capstones_remaining = black_caps;
    b.road_dirty_white = true;
    b.road_dirty_black = true;
}

pub fn boardToTPS(allocator: std.mem.Allocator, b: *const Board) ![]u8 {
    const z = tracy.trace(@src());
    defer z.end();

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 128);
    errdefer buffer.deinit(allocator);
    const writer = buffer.writer(allocator);
    try writer.writeAll("[TPS ");
    for (0..board_size) |row| {
        if (row > 0) {
            try writer.writeByte('/');
        }
        var empty_count: usize = 0;
        var need_comma = false;
        for (0..board_size) |col| {
            const pos = brd.getPos(col, (board_size - 1) - row);
            const sq = &b.squares[pos];
            if (sq.len == 0) {
                empty_count += 1;
            } else {
                if (empty_count > 0) {
                    if (need_comma) {
                        try writer.writeByte(',');
                    }
                    try writer.writeByte('x');
                    if (empty_count > 1) {
                        try writer.print("{d}", .{empty_count});
                    }
                    empty_count = 0;
                    need_comma = true;
                }
                if (need_comma) {
                    try writer.writeByte(',');
                }
                for (0..sq.len) |i| {
                    const piece = sq.stack[i].?;
                    const color_char: u8 = if (piece.color == .White) '1' else '2';
                    try writer.writeByte(color_char);
                    switch (piece.stone_type) {
                        .Flat => {},
                        .Standing => try writer.writeByte('S'),
                        .Capstone => try writer.writeByte('C'),
                    }
                }
                need_comma = true;
            }
        }
        if (empty_count > 0) {
            if (need_comma) {
                try writer.writeByte(',');
            }
            try writer.writeByte('x');
            if (empty_count > 1) {
                try writer.print("{d}", .{empty_count});
            }
        }
    }
    const turn_char: u8 = if (b.to_move == .White) '1' else '2';
    try writer.print(" {c} {d}]", .{ turn_char, b.half_move_count + 1});
    return buffer.toOwnedSlice(allocator);
}
