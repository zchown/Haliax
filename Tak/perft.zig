const std = @import("std");
const brd = @import("src/board.zig");
const mvs = @import("src/moves.zig");
const tps = @import("src/tps.zig");
const ptn = @import("src/ptn.zig");

pub fn runPerft(allocator: *std.mem.Allocator, max_depth: usize, tps_string: []const u8) !void {
    var board = try tps.parseTPS(tps_string);

    const start_time = std.time.milliTimestamp();

    var total_nodes: usize = 0;

    var move_lists = try allocator.alloc(mvs.MoveList, max_depth);
    defer allocator.free(move_lists);

    for (0..max_depth) |i| {
        move_lists[i] = try mvs.MoveList.init((allocator), 256);
    }
    defer {
        for (0..max_depth) |i| {
            move_lists[i].deinit();
        }
    }

    for (1..max_depth + 1) |depth| {
        const depth_start = std.time.milliTimestamp();
        const nodes = try perft(allocator, &board, depth, move_lists);
        const depth_time = std.time.milliTimestamp() - depth_start;

        const nps = if (depth_time > 0)
            @as(u64, @intCast(nodes * 1000)) / @as(u64, @intCast(depth_time))
        else
            0;

        std.debug.print("Depth {d}: {d} nodes in {d}ms ({d} nps)\n", .{ depth, nodes, depth_time, nps });

        total_nodes += nodes;
    }

    const total_time = std.time.milliTimestamp() - start_time;
    const avg_nps = if (total_time > 0)
        @as(u64, @intCast(total_nodes * 1000)) / @as(u64, @intCast(total_time))
    else
        0;

    std.debug.print("\nTotal nodes: {d}\n", .{total_nodes});
    std.debug.print("Total time: {d}ms\n", .{total_time});
    std.debug.print("Average NPS: {d}\n", .{avg_nps});
}

fn perft(allocator: *std.mem.Allocator, board: *brd.Board, depth: usize, move_lists: []mvs.MoveList) !usize {
    if (depth == 0) {
        return 1;
    }

    const result = board.checkResult();
    if (result.ongoing == 0) {
        return 0;
    }

    var nodes: usize = 0;

    var move_list = &move_lists[depth - 1];
    move_list.clear();

    try mvs.generateMoves(board, move_list);

    if (depth == 1) {
        return move_list.count;
    }

    for (move_list.moves[0..move_list.count]) |move| {
        const move_string = try ptn.moveToString(allocator, move, board.to_move);
        std.debug.print("Depth {d}: Trying move {s}\n", .{depth, move_string});
        try mvs.makeMoveWithCheck(board, move);
        std.debug.print("Board after move:\n{s}\n", .{try tps.boardToTPS(allocator.*, board)});
        std.debug.print("Halfmove count: {d}\n", .{board.half_move_count});
        std.debug.print("black stones remaining: {d}\n", .{board.black_stones_remaining});
        const child_nodes = try perft(allocator, board, depth - 1, move_lists);
        try mvs.undoMoveWithCheck(board, move);
        std.debug.print("After undoing move {s}, board is:\n{s}\n", .{move_string, try tps.boardToTPS(allocator.*, board)});
        nodes += child_nodes;
    }

    return nodes;
}

