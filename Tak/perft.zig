const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const tps = @import("tps");
const ptn = @import("ptn");

const mode = @import("builtin").mode;

fn mnpsFromNs(nodes: u64, elapsed_ns: u64) f64 {
    if (elapsed_ns == 0) return 0.0;

    const nodes_f = @as(f64, @floatFromInt(nodes));
    const ns_f = @as(f64, @floatFromInt(elapsed_ns));

    return (nodes_f * 1e3) / ns_f;
}

pub fn runPerft(allocator: *std.mem.Allocator, max_depth: usize, tps_string: []const u8) !void {
    var board = try tps.parseTPS(tps_string);

    var total_nodes: u64 = 0;

    var move_lists = try allocator.alloc(mvs.MoveList, max_depth);
    defer allocator.free(move_lists);

    for (0..max_depth) |i| {
        move_lists[i] = try mvs.MoveList.init(allocator, 256);
    }
    defer {
        for (0..max_depth) |i| move_lists[i].deinit();
    }

    var total_timer = try std.time.Timer.start();

    for (1..max_depth + 1) |depth| {
        var depth_timer = try std.time.Timer.start();

        const nodes_usize = try perft(allocator, &board, depth, move_lists);
        const nodes: u64 = @intCast(nodes_usize);

        const depth_ns = depth_timer.read();
        const mnps = mnpsFromNs(nodes, depth_ns);

        const depth_ms = depth_ns / std.time.ns_per_ms;

        std.debug.print(
            "Depth {d}: {d} nodes in {d}ms ({d:.2} MNPS)\n",
            .{ depth, nodes, depth_ms, mnps },
        );

        total_nodes += nodes;
    }

    const total_ns = total_timer.read();
    const avg_mnps = mnpsFromNs(total_nodes, total_ns);

    std.debug.print("\nTotal nodes: {d}\n", .{total_nodes});
    std.debug.print("Total time: {d}ms\n", .{total_ns / std.time.ns_per_ms});
    std.debug.print("Average speed: {d:.2} MNPS\n", .{avg_mnps});
}

fn perft(allocator: *std.mem.Allocator, board: *brd.Board, depth: usize, move_lists: []mvs.MoveList) !usize {
    if (depth == 0) return 1;

    var nodes: usize = 0;

    var move_list = &move_lists[depth - 1];
    move_list.clear();

    try mvs.generateMoves(board, move_list);

    if (depth == 1) return move_list.count;

    for (move_list.moves[0..move_list.count]) |move| {
        if (mode == .Debug or mode == .ReleaseSafe ) {
            const pre_hash = board.zobrist_hash;
            try mvs.makeMoveWithCheck(board, move);
            const child_nodes = try perft(allocator, board, depth - 1, move_lists);
            try mvs.undoMoveWithCheck(board, move);
            // if (pre_hash != board.zobrist_hash) {
            //     std.debug.print("Zobrist hash mismatch detected!\n", .{});
            //     const tps_str = try tps.boardToTPS(allocator.*, board);
            //     defer allocator.free(tps_str);
            //     std.debug.print("Current TPS: {s}\n", .{tps_str});
            //
            //     const move_ptn = try ptn.moveToString(allocator, move, board.to_move);
            //     defer allocator.free(move_ptn);
            //     std.debug.print("Offending move: {s}\n", .{move_ptn});
            //
            //     return error.ZobristHashMismatch;
            // }
            std.debug.assert(pre_hash == board.zobrist_hash);
            nodes += child_nodes;
        } 
        else {
            mvs.makeMove(board, move);
            const child_nodes = try perft(allocator, board, depth - 1, move_lists);
            mvs.undoMove(board, move);
            nodes += child_nodes;
        }
    }

    return nodes;
}

