const std = @import("std");
const brd = @import("board");
const ptn = @import("ptn");
const tps = @import("tps");

pub const GoParams = struct {
    wtime_ms: ?u64 = null,
    btime_ms: ?u64 = null,
    winc_ms: ?u64 = null,
    binc_ms: ?u64 = null,
    movetime_ms: ?u64 = null,
    depth: ?u32 = null,
    nodes: ?u64 = null,
};

pub const EngineCallbacks = struct {
    ctx: *anyopaque,

    onNewGame: *const fn (ctx: *anyopaque, size: usize) anyerror!void,

    onSetPosition: *const fn (ctx: *anyopaque, b: *brd.Board) anyerror!void,

    onApplyMove: *const fn (ctx: *anyopaque, b: *brd.Board, m: brd.Move) anyerror!void,

    onGo: *const fn (ctx: *anyopaque, b: *brd.Board, params: GoParams) anyerror!brd.Move,

    onStop: *const fn (ctx: *anyopaque) void,
};

pub fn runTEI(
    allocator: std.mem.Allocator,
    callbacks: EngineCallbacks,
    engine_name: []const u8,
    engine_author: []const u8,
) !void {
    var stdin_file = std.io.getStdIn();
    var stdout_file = std.io.getStdOut();

    var br = std.io.bufferedReader(stdin_file.reader());
    var bw = std.io.bufferedWriter(stdout_file.writer());
    const in = br.reader();
    const out = bw.writer();

    var line_buf: [8192]u8 = undefined;

    var board = brd.Board.init();

    const emit = struct {
        fn line(writer: anytype, bw_ref: *std.io.BufferedWriter(4096, @TypeOf(stdout_file.writer())), s: []const u8) !void {
            try writer.writeAll(s);
            try writer.writeByte('\n');
            try bw_ref.flush();
        }
        fn fmt(writer: anytype, bw_ref: *std.io.BufferedWriter(4096, @TypeOf(stdout_file.writer())), comptime f: []const u8, args: anytype) !void {
            try writer.print(f, args);
            try writer.writeByte('\n');
            try bw_ref.flush();
        }
    };

    while (true) {
        const maybe_line = try in.readUntilDelimiterOrEof(&line_buf, '\n');
        if (maybe_line == null) break;

        var raw = maybe_line.?;
        raw = std.mem.trim(u8, raw, " \t\r\n");
        if (raw.len == 0) continue;

        var tok = std.mem.tokenizeAny(u8, raw, " \t");
        const cmd = tok.next() orelse continue;

        if (std.mem.eql(u8, cmd, "tei")) {
            try emit.fmt(out, &bw, "id name {s}", .{engine_name});
            try emit.fmt(out, &bw, "id author {s}", .{engine_author});
            try emit.line(out, &bw, "teiok");
            continue;
        }
        if (std.mem.eql(u8, cmd, "isready")) {
            try emit.line(out, &bw, "readyok");
            continue;
        }
        // TODO: currently ignored
        if (std.mem.eql(u8, cmd, "setoption")) {
            try emit.line(out, &bw, "ok");
            continue;
        }

        if (std.mem.eql(u8, cmd, "teinewgame")) {
            const size_str = tok.next() orelse {
                try callbacks.onNewGame(callbacks.ctx, brd.board_size);
                try emit.line(out, &bw, "ok");
                continue;
            };
            const size = std.fmt.parseInt(usize, size_str, 10) catch brd.board_size;
            if (size != brd.board_size) {
                std.debug.print("Warning: TEI newgame size {d} not supported, using {d}\n", .{size, brd.board_size});
            }
            try callbacks.onNewGame(callbacks.ctx, size);
            board.reset();
            try callbacks.onSetPosition(callbacks.ctx, &board);
            try emit.line(out, &bw, "ok");
            continue;
        }

        if (std.mem.eql(u8, cmd, "position")) {
            const rest = std.mem.trimLeft(u8, raw[cmd.len..], " \t");

            var moves_part: ?[]const u8 = null;
            var pos_part: []const u8 = rest;

            if (std.mem.indexOf(u8, rest, " moves ")) |mi| {
                pos_part = std.mem.trim(u8, rest[0..mi], " \t");
                moves_part = std.mem.trim(u8, rest[mi + " moves ".len ..], " \t");
            }

            if (std.mem.startsWith(u8, pos_part, "startpos")) {
                board.reset();
                try callbacks.onSetPosition(callbacks.ctx, &board);
            } else if (std.mem.startsWith(u8, pos_part, "tps ")) {
                const tps_str = std.mem.trim(u8, pos_part["tps ".len..], " \t");
                board = try tps.parseTPS(tps_str);
                try callbacks.onSetPosition(callbacks.ctx, &board);
            } else {
                // Unknown position form
                std.debug.print("Unknown position command: {s}\n", .{pos_part});
            }

            if (moves_part) |mp| {
                var mtok = std.mem.tokenizeAny(u8, mp, " \t");
                var cur_color: brd.Color = board.to_move;
                while (mtok.next()) |mstr| {
                    const mv = try ptn.parseMove(mstr, cur_color);
                    try callbacks.onApplyMove(callbacks.ctx, &board, mv);
                    cur_color = cur_color.opposite();
                }
            }

            try emit.line(out, &bw, "ok");
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

            const best = try callbacks.onGo(callbacks.ctx, &board, params);

            var a = allocator;
            const ptn_str = try ptn.moveToString(&a, best, board.to_move);
            defer allocator.free(ptn_str);

            try emit.fmt(out, &bw, "bestmove {s}", .{ptn_str});
            continue;
        }

        if (std.mem.eql(u8, cmd, "stop")) {
            callbacks.onStop(callbacks.ctx);
            try emit.line(out, &bw, "ok");
            continue;
        }

        if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "teiquit")) {
            break;
        }

        try emit.line(out, &bw, "ok");
    }
}

