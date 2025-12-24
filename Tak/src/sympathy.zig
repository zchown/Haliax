const std = @import("std");
const brd = @import("board");

pub const patterns: Patterns = blk: {
    @setEvalBranchQuota(1_000_000);
    break :blk Patterns.init();
};

pub const PatternList = struct {
    len: usize,
    items: [128]u8,

    pub fn init() PatternList {
        return .{ .len = 0, .items = [_]u8{0} ** 128 };
    }

    pub fn add(self: *PatternList, p: u8) void {
        self.items[self.len] = p;
        self.len += 1;
    }
};

pub const Patterns = struct {
    patterns: [brd.max_pickup][brd.max_pickup]PatternList,
    crush_patterns: [brd.max_pickup][brd.max_pickup]PatternList,

    pub fn init() Patterns {
        var ps = [_][brd.max_pickup]PatternList{[_]PatternList{PatternList.init()} ** brd.max_pickup} ** brd.max_pickup;
        var cps = [_][brd.max_pickup]PatternList{[_]PatternList{PatternList.init()} ** brd.max_pickup} ** brd.max_pickup;

        for (1..brd.max_pickup + 1) |pickup| {
            for (1..brd.max_pickup + 1) |max_length| {
                generatePatternsForConfig(&ps[pickup - 1][max_length - 1], pickup, max_length);

                generateCrushPatternsForConfig(&cps[pickup - 1][max_length - 1], pickup, max_length);
            }
        }

        return .{ .patterns = ps, .crush_patterns = cps };
    }

    pub fn get(self: *const Patterns, pickup: usize, max_length: usize) []const u8 {
        const list = &self.patterns[pickup - 1][max_length - 1];
        return list.items[0..list.len];
    }

    pub fn getcrush(self: *const Patterns, pickup: usize, max_length: usize) []const u8 {
        const list = &self.crush_patterns[pickup - 1][max_length - 1];
        return list.items[0..list.len];
    }
};

fn generatePatternsForConfig(list: *PatternList, pickup: usize, max_length: usize) void {
    for (1..pickup + 1) |k| {
        const decisions: usize = k - 1;
        const max_moves: usize = if (max_length > 0) max_length - 1 else 0;
        const limit: usize = @as(usize, 1) << @intCast(decisions);
        for (0..limit) |m| {
            const mask: u8 = @intCast(m);
            if (@popCount(mask) > max_moves) continue;
            const value: u8 = (@as(u8, 1) << @intCast(decisions)) | mask;
            list.add(value);
        }
    }
}

fn generateCrushPatternsForConfig(list: *PatternList, pickup: usize, max_length: usize) void {
    if (max_length == 0) return;
    const required_moves: usize = max_length - 1;

    for (1..pickup + 1) |k| {
        if (k < max_length) continue;
        const decisions: usize = k - 1;
        const limit: usize = @as(usize, 1) << @intCast(decisions);

        for (0..limit) |m| {
            const mask: u8 = @intCast(m);
            if (@popCount(mask) != required_moves) continue; // must use full length

            const value: u8 = (@as(u8, 1) << @intCast(decisions)) | mask;

            if ((value & 0b1) == 0) continue;

            list.add(value);
        }
    }
}


