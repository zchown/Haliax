const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const tps = @import("tps");
const perft = @import("perft.zig");
const tracy = @import("tracy");

pub fn main() !void {
    const tr = tracy.trace(@src());
    defer tr.end();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const tps_string = "[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]";
    const tps_string2 = "[TPS x6/x6/x6/x6/x6/x6 1 1]";
    const tps_string3 = "[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]";
    const tps_string4 = "[TPS x4,2,1/x3,1,2,x/x3,1,2,x/x,1,1,1,1,2/x2,2,x,1C,x/2,x3,2112,x 2 11]";
    const tps_string5 = "[TPS 2S,221,1,1,1,x/x,1S,2,x,1,x/x2,2,111112C,1,2/2,2,2,1,112S,1/1,2221C,221,2,2221S,2/2,2,1,x,2S,1 1 39]";

    const max_depth: usize = 4;

    try perft.runPerft(&allocator, max_depth, tps_string);
    try perft.runPerft(&allocator, max_depth, tps_string2);
    try perft.runPerft(&allocator, max_depth, tps_string3);
    try perft.runPerft(&allocator, max_depth, tps_string4);
    try perft.runPerft(&allocator, max_depth, tps_string5);

}
