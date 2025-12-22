const std = @import("std");
const brd = @import("Board.zig");

pub const patterns: Patterns = blk: {
    @setEvalBranchQuota(1000000);
    break :blk Patterns.init();
};

pub const Patterns = struct {
    patterns: [brd.max_pickup][brd.max_pickup]pattern_list,

    const pattern_list = struct {
        len: usize,
        items: [256]u8,

        pub fn init() pattern_list {
            return pattern_list{
                .len = 0,
                .items = [_]u8{0} ** 256,
            };
        }

        pub fn add(self: *pattern_list, p: u8) void {
            self.items[self.len] = p;
            self.len += 1;
        }
    };

    pub fn init() Patterns {
        var ps = [_][brd.max_pickup]pattern_list{[_]pattern_list{pattern_list.init()} ** (brd.max_pickup)} ** (brd.max_pickup);

        for (1..brd.max_pickup + 1) |pickup| {
            for (1..brd.max_pickup + 1) |max_length| {
                for (1..max_length + 1) |actual_length| {
                    if (actual_length > pickup) continue;
                    const num_zeros = pickup - actual_length;
                    const num_ones = actual_length;
                    generatePatternsForConfig(&ps[pickup - 1][max_length - 1], num_zeros, num_ones);
                }
            }
        }

        return Patterns{
            .patterns = ps,
        };
    }

    pub fn get(self: *const Patterns, pickup: usize, max_length: usize) []const u8 {
        return self.patterns[pickup - 1][max_length - 1].items[0..self.patterns[pickup - 1][max_length - 1].len];
    }
};

fn generatePatternsForConfig(list: *Patterns.pattern_list, num_zeros: usize, num_ones: usize) void {
    var pattern: [8]u1 = [_]u1{0} ** 8;
    const pickup = num_zeros + num_ones;
    const start_idx = 8 - pickup;
    generateHelper(list, &pattern, start_idx, num_zeros, num_ones);
}

fn generateHelper(list: *Patterns.pattern_list, pattern: *[8]u1, idx: usize, zeros_left: usize, ones_left: usize) void {
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

fn convertToPattern(p: [8]u1) u8 {
    var result: u8 = 0;
    for (0..8) |i| {
        result = (result << 1) | @as(u8, p[i]);
    }
    return result;
}

test "pattern generation" {
    for (1..brd.max_pickup + 1) |pickup| {
        for (1..brd.max_pickup + 1) |max_length| {
            const pats = patterns.get(pickup, max_length);
            std.debug.print("Pickup: {}, Max Length: {}, Pattern Count: {}\n", .{ pickup, max_length, pats.len });
            std.debug.print("Patterns: ", .{});
            for (pats) |p| {
                std.debug.print("{b:0>8} ", .{p});
            }
            std.debug.print("\n\n", .{});
        }
    }
}

