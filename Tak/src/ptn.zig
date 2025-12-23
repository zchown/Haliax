const std = @import("std");
const Board = @import("board.zig");

pub const PTNParseError = error{
    ParseError,
    DirectionError,
    CountError,
    MoveError,
    PositionError,
    ColorError,
    StoneError,
    SlideError,
    OutOfMemory,
};

pub const PTN = struct {
    site: ?[]const u8 = null,
    event: ?[]const u8 = null,
    date: ?[]const u8 = null,
    time: ?[]const u8 = null,
    player1: ?[]const u8 = null,
    player2: ?[]const u8 = null,
    clock: ?[]const u8 = null,
    result: ?[]const u8 = null,
    size: usize = 0,
    moves: std.ArrayList(Board.Move),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !PTN {
        return PTN{
            .moves = std.ArrayList(Board.Move).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PTN) void {
        if (self.site) |site| self.allocator.free(site);
        if (self.event) |event| self.allocator.free(event);
        if (self.date) |date| self.allocator.free(date);
        if (self.time) |time| self.allocator.free(time);
        if (self.player1) |p1| self.allocator.free(p1);
        if (self.player2) |p2| self.allocator.free(p2);
        if (self.clock) |clock| self.allocator.free(clock);
        if (self.result) |result| self.allocator.free(result);
        self.moves.deinit();
    }
};

pub fn parsePTN(allocator: std.mem.Allocator, input: []const u8) !PTN {
    var ptn = try PTN.init(allocator);
    errdefer ptn.deinit();

    var lines = std.mem.split(u8, input, "\n");
    var flip: u8 = 0;
    var current_color = Board.Color.White;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.startsWith(u8, trimmed, "[Site:")) {
            ptn.site = try allocator.dupe(u8, trimmed[6..]);
        } else if (std.mem.startsWith(u8, trimmed, "[Event:")) {
            ptn.event = try allocator.dupe(u8, trimmed[7..]);
        } else if (std.mem.startsWith(u8, trimmed, "[Date:")) {
            ptn.date = try allocator.dupe(u8, trimmed[6..]);
        } else if (std.mem.startsWith(u8, trimmed, "[Time:")) {
            ptn.time = try allocator.dupe(u8, trimmed[6..]);
        } else if (std.mem.startsWith(u8, trimmed, "[Player1:")) {
            ptn.player1 = try allocator.dupe(u8, trimmed[9..]);
        } else if (std.mem.startsWith(u8, trimmed, "[Player2:")) {
            ptn.player2 = try allocator.dupe(u8, trimmed[9..]);
        } else if (std.mem.startsWith(u8, trimmed, "[Clock:")) {
            ptn.clock = try allocator.dupe(u8, trimmed[7..]);
        } else if (std.mem.startsWith(u8, trimmed, "[Result:")) {
            ptn.result = try allocator.dupe(u8, trimmed[8..]);
        } else if (std.mem.startsWith(u8, trimmed, "[Size:")) {
            const size_str = std.mem.trim(u8, trimmed[6..], " \"]");
            ptn.size = try std.fmt.parseInt(usize, size_str, 10);
        } else if (trimmed.len > 0 and std.ascii.isDigit(trimmed[0])) {
            var tokens = std.mem.tokenize(u8, trimmed, " ");
            _ = tokens.next();

            while (tokens.next()) |token| {
                if (std.mem.indexOf(u8, token, "-") != null or
                    std.mem.indexOf(u8, token, "/") != null)
                {
                    continue;
                }

                const color_to_use = if (flip < 2) current_color.opposite() else current_color;
                const move = try parseMove(token, color_to_use);
                try ptn.moves.append(move);

                if (flip < 2) flip += 1;
                current_color = current_color.opposite();
            }
        }
    }

    return ptn;
}

pub fn parseMove(move_str: []const u8, color: Board.Color) PTNParseError!Board.Move {
    _ = color;

    const crush = move_str.len > 0 and move_str[move_str.len - 1] == '*';
    const str = if (crush) move_str[0 .. move_str.len - 1] else move_str;

    if (str.len == 2 and std.ascii.isAlphabetic(str[0]) and std.ascii.isDigit(str[1])) {
        const pos = try parsePosition(str);
        return Board.createPlaceMove(pos, .Flat);
    } else if (str.len == 3 and str[0] == 'S' and std.ascii.isAlphabetic(str[1]) and std.ascii.isDigit(str[2])) {
        const pos = try parsePosition(str[1..]);
        return Board.createPlaceMove(pos, .Standing);
    } else if (str.len == 3 and str[0] == 'C' and std.ascii.isAlphabetic(str[1]) and std.ascii.isDigit(str[2])) {
        const pos = try parsePosition(str[1..]);
        return Board.createPlaceMove(pos, .Capstone);
    } else {
        return parseSlideMove(str, crush);
    }
}

fn parseSlideMove(str: []const u8, crush: bool) PTNParseError!Board.Move {
    _ = crush;

    var ptr: usize = 0;
    var count: u8 = 1;

    if (ptr < str.len and std.ascii.isDigit(str[ptr])) {
        count = str[ptr] - '0';
        ptr += 1;
    }

    if (ptr + 2 > str.len) return PTNParseError.PositionError;
    const pos = try parsePosition(str[ptr .. ptr + 2]);
    ptr += 2;

    if (ptr >= str.len) return PTNParseError.DirectionError;
    const dir = try charToDirection(str[ptr]);
    ptr += 1;

    var pattern: u8 = 0;
    var drop_count: u8 = 0;

    while (ptr < str.len and std.ascii.isDigit(str[ptr])) {
        if (drop_count >= 5) return PTNParseError.CountError;
        const drop_value = str[ptr] - '0';
        pattern |= @as(u8, drop_value) << @intCast(drop_count * 3);
        drop_count += 1;
        ptr += 1;
    }

    if (drop_count == 0) {
        pattern = count;
    }

    return Board.createSlideMove(pos, dir, pattern);
}

fn parsePosition(str: []const u8) PTNParseError!Board.Position {
    if (str.len < 2) return PTNParseError.PositionError;

    const col = str[0];
    const row = str[1];

    if (!std.ascii.isAlphabetic(col) or !std.ascii.isDigit(row)) {
        return PTNParseError.PositionError;
    }

    const x = std.ascii.toLower(col) - 'a';
    const y = row - '1';

    if (x >= Board.board_size or y >= Board.board_size) {
        return PTNParseError.PositionError;
    }

    return Board.getPos(@intCast(x), @intCast(y));
}

fn charToDirection(c: u8) PTNParseError!Board.Direction {
    return switch (c) {
        '+' => .North,
        '-' => .South,
        '>' => .East,
        '<' => .West,
        else => PTNParseError.DirectionError,
    };
}

pub fn directionToChar(dir: Board.Direction) u8 {
    return switch (dir) {
        .North => '+',
        .South => '-',
        .East => '>',
        .West => '<',
    };
}

pub fn moveToString(allocator: std.mem.Allocator, move: Board.Move, color: Board.Color) ![]u8 {
    _ = color;

    const x = Board.getX(move.position);
    const y = Board.getY(move.position);

    if (move.pattern == 0) {
        const stone_type: Board.StoneType = @enumFromInt(move.flag);
        const prefix = switch (stone_type) {
            .Flat => "",
            .Standing => "S",
            .Capstone => "C",
        };
        return std.fmt.allocPrint(allocator, "{s}{c}{d}", .{ prefix, @as(u8, 'a') + @as(u8, @intCast(x)), y + 1 });
    } else {
        const dir: Board.Direction = @enumFromInt(move.flag);
        const dir_char = directionToChar(dir);

        var pickup_count: u8 = 0;
        var drops = std.ArrayList(u8).init(allocator);
        defer drops.deinit();

        var temp_pattern = move.pattern;
        while (temp_pattern > 0) {
            const drop = @as(u8, @intCast(temp_pattern & 0b111));
            try drops.append(drop);
            pickup_count += drop;
            temp_pattern >>= 3;
        }

        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        if (pickup_count > 1) {
            try result.append('0' + pickup_count);
        }

        try result.append(@as(u8, 'a') + @as(u8, @intCast(x)));
        try result.append('0' + @as(u8, @intCast(y + 1)));

        try result.append(dir_char);

        if (drops.items.len > 1) {
            for (drops.items) |drop| {
                try result.append('0' + drop);
            }
        }

        return result.toOwnedSlice();
    }
}

test "parse PTN with game result notation" {
    const allocator = std.testing.allocator;
    const ptn_text =
        \\[Size: 6]
        \\
        \\1. a1 f6
        \\2. b2 R-0
    ;

    var ptn = try parsePTN(allocator, ptn_text);
    defer ptn.deinit();

    try std.testing.expectEqual(@as(usize, 3), ptn.moves.items.len);
}

test "parse empty PTN" {
    const allocator = std.testing.allocator;
    const ptn_text = "";

    var ptn = try parsePTN(allocator, ptn_text);
    defer ptn.deinit();

    try std.testing.expectEqual(@as(usize, 0), ptn.moves.items.len);
}

test "parse PTN with blank lines" {
    const allocator = std.testing.allocator;
    const ptn_text =
        \\[Size: 6]
        \\
        \\
        \\1. a1 f6
        \\
        \\2. b2 e5
        \\
    ;

    var ptn = try parsePTN(allocator, ptn_text);
    defer ptn.deinit();

    try std.testing.expectEqual(@as(usize, 4), ptn.moves.items.len);
}

test "char to direction conversions" {
    try std.testing.expectEqual(Board.Direction.North, try charToDirection('+'));
    try std.testing.expectEqual(Board.Direction.South, try charToDirection('-'));
    try std.testing.expectEqual(Board.Direction.East, try charToDirection('>'));
    try std.testing.expectEqual(Board.Direction.West, try charToDirection('<'));

    try std.testing.expectError(PTNParseError.DirectionError, charToDirection('x'));
}

test "direction to char conversions" {
    try std.testing.expectEqual(@as(u8, '+'), directionToChar(.North));
    try std.testing.expectEqual(@as(u8, '-'), directionToChar(.South));
    try std.testing.expectEqual(@as(u8, '>'), directionToChar(.East));
    try std.testing.expectEqual(@as(u8, '<'), directionToChar(.West));
}

test "move to string - flat placement" {
    const allocator = std.testing.allocator;
    const move = Board.createPlaceMove(Board.getPos(2, 3), .Flat);
    const str = try moveToString(allocator, move, .White);
    defer allocator.free(str);

    try std.testing.expectEqualStrings("c4", str);
}

test "move to string - standing stone" {
    const allocator = std.testing.allocator;
    const move = Board.createPlaceMove(Board.getPos(0, 0), .Standing);
    const str = try moveToString(allocator, move, .White);
    defer allocator.free(str);

    try std.testing.expectEqualStrings("Sa1", str);
}

test "move to string - capstone" {
    const allocator = std.testing.allocator;
    const move = Board.createPlaceMove(Board.getPos(5, 5), .Capstone);
    const str = try moveToString(allocator, move, .White);
    defer allocator.free(str);

    try std.testing.expectEqualStrings("Cf6", str);
}

test "parse and convert back - round trip" {
    const allocator = std.testing.allocator;

    const test_cases = [_][]const u8{
        "a1",
        "Sa3",
        "Cf6",
        "a1+",
        "b2-",
        "c3>",
        "d4<",
    };

    for (test_cases) |original| {
        const move = try parseMove(original, .White);
        const converted = try moveToString(allocator, move, .White);
        defer allocator.free(converted);

        try std.testing.expectEqualStrings(original, converted);
    }
}
