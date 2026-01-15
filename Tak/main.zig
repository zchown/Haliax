const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const tps = @import("tps");
const perft = @import("perft.zig");
const tracy = @import("tracy");

pub fn main() !void {
    const tr = tracy.traceNamed(@src(), "Main Trace");
    defer tr.end();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();


    tracy.frameMarkNamed("TPS Perft Tests");
    {
        const z = tracy.traceNamed(@src(), "TPS Perft Test");
        defer z.end();
        const tps_string = "[TPS x6/x6/x6/x6/x6/x6 1 1]";
        const tps_string2 = "[TPS 2,2,21S,2,2,2/2,x,222221,2,2,x/1,1,2221C,x,111112C,2S/x,1,2S,x2,121211212/1,1,1212S,1S,2,1S/x2,2,1,21,1 1 42]";
        const tps_string3 = "[TPS 2,2,2,2,1,1/2,2,x2,1,2/1,2,2,1,1,2/1,2,1,2,1,2/1,1,1,2,2,2/1,1,1,1,1,2 1 18]";
        const tps_string4 = "[TPS 2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/1S,1S,1S,1S,1S,1S/2S,2S,2S,2S,2S,2S/11,x5 1 3]";
        const tps_string5 = "[TPS 2,2,21S,12122,221,x/x,1222211C,x,12C,2,x/x,12,2,x3/2,1,1S,1,1,1/x,2,12S,1,1,1/x,2,x3,1 2 33]";

        const max_depth: usize = 4;

        std.debug.print("{s}\n", .{tps_string});
        try perft.runPerft(&allocator, max_depth, tps_string);
        std.debug.print("{s}\n", .{tps_string2});
        try perft.runPerft(&allocator, max_depth, tps_string2);
        std.debug.print("{s}\n", .{tps_string3});
        try perft.runPerft(&allocator, max_depth, tps_string3);
        std.debug.print("{s}\n", .{tps_string4});
        try perft.runPerft(&allocator, max_depth, tps_string4);
        std.debug.print("{s}\n", .{tps_string5});
        try perft.runPerft(&allocator, max_depth, tps_string5);
    }
    tracy.frameMarkNamed("Done");

    return;
}
