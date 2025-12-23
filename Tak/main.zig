const std = @import("std");
const brd = @import("src/board.zig");
const mvs = @import("src/moves.zig");
const perft = @import("perft.zig");
const tps = @import("src/tps.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const tps_string = "[TPS x6/x6/x6/x6/x6/x6 0 1]";

    const max_depth: usize = 5;

    try perft.runPerft(&allocator, max_depth, tps_string);
}
