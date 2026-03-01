const std = @import("std");
const brd = @import("board");
const ptn = @import("ptn");
const tps = @import("tps");
const eng = @import("engine");
const tt = @import("transposition");

const start_pos_tps = "[TPS x6/x6/x6/x6/x6/x6 1 1]";

pub const GoParams = struct {
    wtime_ms: ?u64 = null,
    btime_ms: ?u64 = null,
    winc_ms: ?u64 = null,
    binc_ms: ?u64 = null,
    movetime_ms: ?u64 = null,
    depth: ?u32 = null,
    nodes: ?u64 = null,
};

pub fn runTEI(
    allocator: *std.mem.Allocator,
    engine: *eng.Engine,
    engine_name: []const u8,
    engine_author: []const u8,
) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    while (true) {
        const raw_line = stdin.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            error.StreamTooLong => return err,
            else => return err,
        };
        const trimmed = std.mem.trim(u8, raw_line, " \t\r\n");
        if (trimmed.len == 0) continue;

        var tok = std.mem.tokenizeAny(u8, trimmed, " \t");
        const cmd = tok.next() orelse continue;

        if (std.mem.eql(u8, cmd, "tei")) {
            try stdout.print("id name {s}\n", .{engine_name});
            try stdout.print("id author {s}\n", .{engine_author});
            try stdout.print("option name HalfKomi type spin default 0 min 0 max 10\n", .{});
            try stdout.print("option name Hash type spin default 64 min 1 max 4096\n", .{});
            try stdout.print("teiok\n", .{});
            try stdout.flush();
            continue;
        }

        if (std.mem.eql(u8, cmd, "isready")) {
            try stdout.print("readyok\n", .{});
            try stdout.flush();
            continue;
        }

        if (std.mem.eql(u8, cmd, "setoption")) {
            var opt_name: ?[]const u8 = null;
            var opt_value: ?[]const u8 = null;

            while (tok.next()) |t| {
                if (std.mem.eql(u8, t, "name")) {
                    opt_name = tok.next();
                } else if (std.mem.eql(u8, t, "value")) {
                    opt_value = tok.next();
                }
            }

            if (opt_name) |n| {
                if (std.mem.eql(u8, n, "HalfKomi")) {
                    if (opt_value) |v| {
                        const half = std.fmt.parseInt(i32, v, 10) catch continue;
                        brd.komi = @as(f32, @floatFromInt(half)) * 0.5;
                    }
                } else if (std.mem.eql(u8, n, "Hash")) {
                    if (opt_value) |v| {
                        const new_size = std.fmt.parseInt(usize, v, 10) catch continue;
                        engine.tt_table.deinit(allocator);
                        engine.tt_table = try tt.TranspositionTable.init(allocator, new_size);
                        engine.searcher.tt_table = &engine.tt_table;
                        engine.hash_size_mb = new_size;
                    }
                }
            }
            try stdout.print("ok\n", .{});
            try stdout.flush();
            continue;
        }

        if (std.mem.eql(u8, cmd, "option")) {
            try stdout.print("option name HalfKomi type spin default 0 min 0 max 10\n", .{});
            try stdout.print("option name Hash type spin default 64 min 1 max 4096\n", .{});
            try stdout.flush();
            continue;
        }

        if (std.mem.eql(u8, cmd, "teinewgame")) {
            const size_str = tok.next();
            var size: usize = brd.board_size;
            if (size_str) |s| {
                size = std.fmt.parseInt(usize, s, 10) catch brd.board_size;
            }
            if (size != brd.board_size) {
                std.debug.print("Warning: TEI newgame size {d} ≠ compiled size {d}\n", .{ size, brd.board_size });
            }
            try engine.onNewGame(size);
            try engine.onSetPosition(start_pos_tps);
            try stdout.print("ok\n", .{});
            try stdout.flush();
            continue;
        }

        if (std.mem.eql(u8, cmd, "debug")) {
            const tps_str = try tps.boardToTPS(allocator.*, &engine.board);
            defer allocator.free(tps_str);
            std.debug.print("Debug TPS: {s}\n", .{tps_str});
            continue;
        }

        if (std.mem.eql(u8, cmd, "position")) {
            const rest = std.mem.trimLeft(u8, trimmed[cmd.len..], " \t");

            var moves_part: ?[]const u8 = null;
            var pos_part: []const u8 = rest;

            if (std.mem.indexOf(u8, rest, " moves ")) |mi| {
                pos_part = std.mem.trim(u8, rest[0..mi], " \t");
                moves_part = std.mem.trim(u8, rest[mi + " moves ".len ..], " \t");
            }

            if (std.mem.startsWith(u8, pos_part, "startpos")) {
                try engine.onSetPosition(start_pos_tps);
            } else if (std.mem.startsWith(u8, pos_part, "tps ")) {
                const tps_str = std.mem.trim(u8, pos_part["tps ".len..], " \t");
                try engine.onSetPosition(tps_str);
            } else {
                std.debug.print("Unknown position command: {s}\n", .{pos_part});
            }

            if (moves_part) |mp| {
                var mtok = std.mem.tokenizeAny(u8, mp, " \t");
                while (mtok.next()) |mstr| {
                    const mv = try ptn.parseMove(mstr);
                    try engine.onApplyMove(mv);
                }
            }

            try stdout.print("ok\n", .{});
            try stdout.flush();
            continue;
        }

        if (std.mem.eql(u8, cmd, "go")) {
            var params = GoParams{};

            while (tok.next()) |k| {
                if (std.mem.eql(u8, k, "wtime")) {
                    if (tok.next()) |v| params.wtime_ms = std.fmt.parseInt(u64, v, 10) catch null;
                } else if (std.mem.eql(u8, k, "btime")) {
                    if (tok.next()) |v| params.btime_ms = std.fmt.parseInt(u64, v, 10) catch null;
                } else if (std.mem.eql(u8, k, "winc")) {
                    if (tok.next()) |v| params.winc_ms = std.fmt.parseInt(u64, v, 10) catch null;
                } else if (std.mem.eql(u8, k, "binc")) {
                    if (tok.next()) |v| params.binc_ms = std.fmt.parseInt(u64, v, 10) catch null;
                } else if (std.mem.eql(u8, k, "movetime")) {
                    if (tok.next()) |v| params.movetime_ms = std.fmt.parseInt(u64, v, 10) catch null;
                } else if (std.mem.eql(u8, k, "depth")) {
                    if (tok.next()) |v| params.depth = std.fmt.parseInt(u32, v, 10) catch null;
                } else if (std.mem.eql(u8, k, "nodes")) {
                    if (tok.next()) |v| params.nodes = std.fmt.parseInt(u64, v, 10) catch null;
                } else {
                    std.debug.print("Unknown go param: {s}\n", .{k});
                }
            }

            const best = try engine.onGo(params);

            const ptn_str = try ptn.moveToString(allocator, best);
            defer allocator.free(ptn_str);

            try stdout.print("bestmove {s}\n", .{ptn_str});
            try stdout.flush();
            continue;
        }

        if (std.mem.eql(u8, cmd, "stop")) {
            engine.onStop();
            try stdout.print("ok\n", .{});
            try stdout.flush();
            continue;
        }

        if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "teiquit")) {
            break;
        }

        try stdout.print("ok\n", .{});
        try stdout.flush();
    }
}
