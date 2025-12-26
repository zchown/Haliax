const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const tps = @import("tps");
const perft = @import("perft.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const tps_string = "[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]";
    // const tps_string = "[TPS x6/x6/x6/x6/x6/x6 1 1]";

    const max_depth: usize = 5;

    try perft.runPerft(&allocator, max_depth, tps_string);
}
