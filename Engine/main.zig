const std = @import("std");
const engine = @import("engine");
const tei = @import("tei");
const tracy = @import("tracy");

pub fn main() !void {
    const z = tracy.trace(@src());
    defer z.end();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var eng = try engine.Engine.init(&allocator, "/Users/zanderchown/ComputerScience/Personal/Haliax/runs/run2/tak_net.onnx");
    defer eng.deinit();

    try tei.runTEI(allocator, &eng, "Haliax", "Zander Chown");
}
