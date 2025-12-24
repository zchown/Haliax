const std = @import("std");
const brd = @import("board");

pub const patterns: Patterns = blk: {
    @setEvalBranchQuota(1000000);
    break :blk Patterns.init();
};
pub const PatternList = struct {
    len: usize,
    items: [128]u8,

    pub fn init() PatternList {
        return PatternList{
            .len = 0,
            .items = [_]u8{0} ** 128,
        };
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
        var ps = [_][brd.max_pickup]PatternList{[_]PatternList{PatternList.init()} ** (brd.max_pickup)} ** (brd.max_pickup);
        var eps = [_][brd.max_pickup]PatternList{[_]PatternList{PatternList.init()} ** (brd.max_pickup)} ** (brd.max_pickup);

        for (1..brd.max_pickup + 1) |pickup| {
            for (1..brd.max_pickup + 1) |max_length| {
                for (1..max_length + 1) |actual_length| {
                    if (actual_length > pickup) continue;
                    const num_zeros = pickup - actual_length;
                    const num_ones = actual_length;
                    generatePatternsForConfig(&ps[pickup - 1][max_length - 1], num_zeros, num_ones);
                }

                if (max_length <= pickup) {
                    const num_zeros = pickup - max_length;
                    const num_ones = max_length;
                    generatecrushPatternsForConfig(&eps[pickup - 1][max_length - 1], num_zeros, num_ones);
                }
            }
        }

        return Patterns{
            .patterns = ps,
            .crush_patterns = eps,
        };
    }

    pub fn get(self: *const Patterns, pickup: usize, max_length: usize) []const u8 {
        return self.patterns[pickup - 1][max_length - 1].items[0..self.patterns[pickup - 1][max_length - 1].len];
    }

    pub fn getcrush(self: *const Patterns, pickup: usize, max_length: usize) []const u8 {
        return self.crush_patterns[pickup - 1][max_length - 1].items[0..self.crush_patterns[pickup - 1][max_length - 1].len];
    }
};

fn generatePatternsForConfig(list: *PatternList, num_zeros: usize, num_ones: usize) void {
    var pattern: [8]u1 = [_]u1{0} ** 8;
    const pickup = num_zeros + num_ones;
    const start_idx = 8 - pickup;
    generateHelper(list, &pattern, start_idx, num_zeros, num_ones);
}

fn generatecrushPatternsForConfig(list: *PatternList, num_zeros: usize, num_ones: usize) void {
    var pattern: [8]u1 = [_]u1{0} ** 8;
    const pickup = num_zeros + num_ones;
    const start_idx = 8 - pickup;
    pattern[7] = 1;
    generatecrushHelper(list, &pattern, start_idx, num_zeros, num_ones - 1);
}

fn generateHelper(list: *PatternList, pattern: *[8]u1, idx: usize, zeros_left: usize, ones_left: usize) void {
    if (zeros_left == 0 and ones_left == 0) {
        list.add(convertToPattern(pattern.*));
        return;
    }
    if (idx >= 8) return;

    if (zeros_left > 0) {
        pattern.*[idx] = 0;
        generateHelper(list, pattern, idx + 1, zeros_left - 1, ones_left);
        pattern.*[idx] = 0;
    }

    if (ones_left > 0) {
        pattern.*[idx] = 1;
        generateHelper(list, pattern, idx + 1, zeros_left, ones_left - 1);
        pattern.*[idx] = 0;
    }
}

fn generatecrushHelper(list: *PatternList, pattern: *[8]u1, idx: usize, zeros_left: usize, ones_left: usize) void {
    if (zeros_left == 0 and ones_left == 0) {
        list.add(convertToPattern(pattern.*));
        return;
    }
    if (idx >= 7) return;

    if (zeros_left > 0) {
        pattern.*[idx] = 0;
        generatecrushHelper(list, pattern, idx + 1, zeros_left - 1, ones_left);
        pattern.*[idx] = 0;
    }

    if (ones_left > 0) {
        pattern.*[idx] = 1;
        generatecrushHelper(list, pattern, idx + 1, zeros_left, ones_left - 1);
        pattern.*[idx] = 0;
    }
}

fn convertToPattern(p: [8]u1) u8 {
    var result: u8 = 0;
    for (0..8) |i| {
        result = (result << 1) | @as(u8, p[i]);
    }
    return result;
}

