const std = @import("std");
const brd = @import("board");

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
    moves: std.ArrayList(brd.Move),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !PTN {
        return PTN{
            .moves = try std.ArrayList(brd.Move).initCapacity(allocator, 256),
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
        self.moves.deinit(self.allocator);
    }
};

pub fn parsePTN(allocator: std.mem.Allocator, input: []const u8) !PTN {
    var ptn = try PTN.init(allocator);
    errdefer ptn.deinit();

    var lines = std.mem.splitSequence(u8, input, "\n");
    var flip: u8 = 0;
    var current_color = brd.Color.White;

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
            var tokens = std.mem.splitSequence(u8, trimmed, " ");
            _ = tokens.next();

            while (tokens.next()) |token| {
                if (std.mem.indexOf(u8, token, "/") != null
                    or std.mem.indexOf(u8, token, "R") != null
                    ) {
                    continue;
                }

                const move = try parseMove(token);
                try ptn.moves.append(allocator, move);

                if (flip < 2) flip += 1;
                current_color = current_color.opposite();
            }
        }
    }

    return ptn;
}

pub fn parseMove(move_str: []const u8) PTNParseError!brd.Move {
    const crush = move_str.len > 0 and move_str[move_str.len - 1] == '*';
    const str = if (crush) move_str[0 .. move_str.len - 1] else move_str;

    if (str.len == 2 and std.ascii.isAlphabetic(str[0]) and std.ascii.isDigit(str[1])) {
        const pos = try parsePosition(str);
        return brd.Move.createPlaceMove(pos, .Flat);
    } else if (str.len == 3 and str[0] == 'S' and std.ascii.isAlphabetic(str[1]) and std.ascii.isDigit(str[2])) {
        const pos = try parsePosition(str[1..]);
        return brd.Move.createPlaceMove(pos, .Standing);
    } else if (str.len == 3 and str[0] == 'C' and std.ascii.isAlphabetic(str[1]) and std.ascii.isDigit(str[2])) {
        const pos = try parsePosition(str[1..]);
        return brd.Move.createPlaceMove(pos, .Capstone);
    } else {
        return parseSlideMove(str, crush);
    }
}

fn parseSlideMove(str: []const u8, crush: bool) PTNParseError!brd.Move {
    var ptr: usize = 0;
    var count: u8 = 1;

    if (str.len == 3 or (str.len == 4 and crush)) {
        const pos = try parsePosition(str[0 .. 2]);
        const dir = try charToDirection(str[2]);
        return brd.Move.createSlideMove(pos, dir, 1);
    } 
    else if (str.len == 4 or (str.len == 5 and crush)) {
        const pos = try parsePosition(str[1 .. 3]);
        const dir = try charToDirection(str[3]);
        const drop = str[0];
        var pattern: u8 = 1;
        pattern <<= @as(u3, @intCast((drop - '0') - 1));
        return brd.Move.createSlideMove(pos, dir, pattern);
    }

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

    var pattern_array: [8]u1 = [_]u1{0, 0, 0, 0, 0, 0, 0, 0};
    var idx = 8 - count;
    while (ptr < str.len and idx < 8) {
        if (!std.ascii.isDigit(str[ptr])) {
            return PTNParseError.CountError;
        }
        const cur = str[ptr] - '0';
        ptr += 1;
        // std.debug.print("Drop count: {d} at index {d}\n", .{cur, idx});
        pattern_array[idx] = 1;
        idx += cur;
    }

    var pattern: u8 = 0;
    // convert pattern_array to pattern
    for (0..8) |i| {
        // std.debug.print("pattern_array[{d}] = {d}\n", .{i, pattern_array[i]});
        pattern <<= 1;
        pattern |= pattern_array[i];
    }

    return brd.Move.createSlideMove(pos, dir, pattern);
}

fn parsePosition(str: []const u8) PTNParseError!brd.Position {
    if (str.len < 2) return PTNParseError.PositionError;

    const col = str[0];
    const row = str[1];

    if (!std.ascii.isAlphabetic(col) or !std.ascii.isDigit(row)) {
        std.debug.print("Invalid position format: {s}\n", .{str});
        return PTNParseError.PositionError;
    }

    const x = std.ascii.toLower(col) - 'a';
    const y = row - '1';

    if (x >= brd.board_size or y >= brd.board_size) {
        return PTNParseError.PositionError;
    }

    return brd.getPos(@intCast(x), @intCast(y));
}

fn charToDirection(c: u8) PTNParseError!brd.Direction {
    return switch (c) {
        '+' => .North,
        '-' => .South,
        '>' => .East,
        '<' => .West,
        else => PTNParseError.DirectionError,
    };
}

pub fn directionToChar(dir: brd.Direction) u8 {
    return switch (dir) {
        .North => '+',
        .South => '-',
        .East => '>',
        .West => '<',
    };
}

pub fn moveToString(allocator: *std.mem.Allocator, move: brd.Move) ![]u8 {
    const x = brd.getX(move.position);
    const y = brd.getY(move.position);

    if (move.pattern == 0) {
        const stone_type: brd.StoneType = @enumFromInt(move.flag);
        const prefix = switch (stone_type) {
            .Flat => "",
            .Standing => "S",
            .Capstone => "C",
        };
        return std.fmt.allocPrint(allocator.*, "{s}{c}{d}", .{ prefix, @as(u8, 'a') + @as(u8, @intCast(x)), y + 1 });
    } else {
        const dir: brd.Direction = @enumFromInt(move.flag);
        const dir_char = directionToChar(dir);

        var result = try std.ArrayList(u8).initCapacity(allocator.*, 16);
        defer result.deinit(allocator.*);

        const pickup_count: u8 = @intCast(move.movedStones());
        if (pickup_count > 1) {
            try result.append(allocator.*, '0' + pickup_count);
        }

        try result.append(allocator.*, @as(u8, 'a') + @as(u8, @intCast(x)));
        try result.append(allocator.*, '0' + @as(u8, @intCast(y + 1)));

        try result.append(allocator.*, dir_char);

        if (pickup_count > 1) {
            var drops: [8]u8 = [_]u8{'0', '0', '0', '0', '0', '0', '0', '0'};

            // iterate through pattern bits
            var drop_idx: usize = 0;
            for (0..8) |i| {
                const bit = (move.pattern >> (7 - @as(u3, @intCast(i)))) & 1;
                if (bit == 1) {
                    drop_idx += 1;
                }

                if (drop_idx >= 1) {
                    drops[drop_idx - 1] += 1;
                }
            }

            if (drops[1] != '0') {
                for (0..8) |i| {
                    if (drops[i] > '0') {
                        try result.append(allocator.*, drops[i]);
                    }
                }
            }
        }

        return result.toOwnedSlice(allocator.*);
    }
}
