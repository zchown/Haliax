const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const mcts = @import("tree_search");
const nn = @import("nn_eval");

const magic: []const u8 = "TAKDATA1";
const search_params = mcts.SearchParams{
    .max_simulations = 100,
    .max_time_ms = 0,
};

const PolicyHeads = struct {
    place_pos: [brd.num_squares]f32,
    place_type: [brd.num_piece_types]f32,
    slide_from: [brd.num_squares]f32,
    slide_dir: [brd.num_directions]f32,
    slide_pickup: [brd.max_pickup]f32,
    slide_len: [6]f32,
};

const BufferedStep = struct {
    features: []f32, // owned
    to_move: brd.Color,
    heads: PolicyHeads,
};

const GameData = struct {
    steps: []BufferedStep,
    winner: ?brd.Color,
};

fn writeU32LE(w: anytype, v: u32) !void {
    try w.writeInt(u32, v, .little);
}

fn writeF32LE(w: anytype, v: f32) !void {
    const bits: u32 = @bitCast(v);
    try w.writeInt(u32, bits, .little);
}

fn writeF32SliceLE(w: anytype, xs: []const f32) !void {
    for (xs) |v| try writeF32LE(w, v);
}

fn writeHeader(w: anytype, channels_in: u32) !void {
    if (magic.len != 8) @compileError("MAGIC must be exactly 8 bytes");
    try w.writeAll(magic);
    try writeU32LE(w, channels_in);
    try writeU32LE(w, 0);
}

fn zeroHeads(h: *PolicyHeads) void {
    @memset(&h.place_pos, 0);
    @memset(&h.place_type, 0);
    @memset(&h.slide_from, 0);
    @memset(&h.slide_dir, 0);
    @memset(&h.slide_pickup, 0);
    @memset(&h.slide_len, 0);
}

fn clampPickupToHeadIndex(pickup: usize) usize {
    var p = pickup;
    if (p < 1) p = 1;
    if (p > brd.max_pickup) p = brd.max_pickup;
    return p - 1;
}

fn scatterPolicyFromRootStats(stats: mcts.RootStats, h: *PolicyHeads) void {
    zeroHeads(h);

    const moves = stats.moves;
    const visits = stats.visit_counts;
    if (moves.len == 0 or moves.len != visits.len) return;

    var sum: f32 = 0;
    for (visits) |v| sum += @floatFromInt(v);
    if (sum <= 0) return;

    for (moves, 0..) |mv, i| {
        const p: f32 = @as(f32, @floatFromInt(visits[i])) / sum;
        const pos_idx: usize = @intCast(mv.position);

        // Place
        if (mv.pattern == 0) {
            if (pos_idx < brd.num_squares) h.place_pos[pos_idx] += p;

            const st: usize = @intCast(mv.flag);
            if (st < brd.num_piece_types) h.place_type[st] += p;
        } else { // Slide
            if (pos_idx < brd.num_squares) h.slide_from[pos_idx] += p;

            const dir: usize = @intCast(mv.flag);
            if (dir < brd.num_directions) h.slide_dir[dir] += p;

            const moved: usize = mv.movedStones();
            const pickup_i = clampPickupToHeadIndex(moved);
            h.slide_pickup[pickup_i] += p;

            const ones_u8: u8 = @intCast(@popCount(mv.pattern));
            if (ones_u8 >= 1 and ones_u8 <= 6) {
                h.slide_len[ones_u8 - 1] += p;
            }
        }
    }
}

fn writeRecord(
    w: anytype,
    channels_in: u32,
    features: []const f32,
    h: *const PolicyHeads,
    z: f32,
) !void {
    if (features.len != brd.num_squares * @as(usize, channels_in)) return error.BadFeaturesLength;

    try writeF32SliceLE(w, features);

    try writeF32SliceLE(w, h.place_pos[0..]);
    try writeF32SliceLE(w, h.place_type[0..]);
    try writeF32SliceLE(w, h.slide_from[0..]);
    try writeF32SliceLE(w, h.slide_dir[0..]);
    try writeF32SliceLE(w, h.slide_pickup[0..]);
    try writeF32SliceLE(w, h.slide_len[0..]);

    try writeF32LE(w, z);
}

fn freeBufferedSteps(allocator: std.mem.Allocator, steps: []BufferedStep) void {
    for (steps) |s| allocator.free(s.features);
    allocator.free(steps);
}

fn computeWinner(board: *brd.Board) ?brd.Color {
    const r = board.checkResult();
    if (r.ongoing == 1) {
        if (board.white_vector.data[25 * 36 + 5] > 0) {
            return brd.Color.White;
        } else if (board.black_vector.data[25 * 36 + 5] > 0) {
            return brd.Color.Black;
        }
    }

    if (r.road == 1 or r.flat == 1) {
        if (r.road == 1) {
            std.debug.print("Road win detected\n", .{});
        }
        if (r.color == 1) {
            return brd.Color.White;
        } else {
            return brd.Color.Black;
        }
    }

    return null; // draw or ongoing
}

fn outcomeZFromWinner(to_move: brd.Color, winner: ?brd.Color) f32 {
    if (winner == null) return 0.0;
    return if (winner.? == to_move) 1.0 else -1.0;
}

pub fn playSelfGameBuffered(
    allocator: *std.mem.Allocator,
    tree_search: *mcts.MonteCarloTreeSearch,
    max_plies: usize,
) !GameData {
    var board = brd.Board.init();
    board.updateAllVectors();

    var steps = try std.ArrayList(BufferedStep).initCapacity(allocator.*, max_plies);

    var ply: usize = 0;
    while (ply < max_plies) : (ply += 1) {
        if (board.checkResult().ongoing == 0) break;

        const mv = try tree_search.search(&board, search_params);

        const src = if (board.to_move == .White)
            board.white_vector.data
        else
            board.black_vector.data;

        if (src.len % brd.num_squares != 0) return error.BadVectorLength;
        const channels_in: usize = src.len / brd.num_squares;

        const feat = try allocator.alloc(f32, src.len);
        std.mem.copyForwards(f32, feat, &src);

        var step = BufferedStep{
            .features = feat,
            .to_move = board.to_move,
            .heads = undefined,
        };

        if (tree_search.getLastRootStats()) |stats| {
            scatterPolicyFromRootStats(stats, &step.heads);
        } else {
            // Fallback: uniform heads over legal moves if RootStats is unavailable.
            // Shouln't happen
            zeroHeads(&step.heads);

            var tmp_moves = mvs.MoveList.init(allocator, 512) catch return error.OOM;
            defer tmp_moves.deinit();
            tmp_moves.clear();
            try mvs.generateMoves(&board, &tmp_moves);

            const n = tmp_moves.count;
            if (n > 0) {
                const u: f32 = 1.0 / @as(f32, @floatFromInt(n));
                for (tmp_moves.moves[0..n]) |lm| {
                    const pos_idx: usize = @intCast(lm.position);
                    if (lm.pattern == 0) {
                        if (pos_idx < brd.num_squares) step.heads.place_pos[pos_idx] += u;
                        const st: usize = @intCast(lm.flag);
                        if (st < brd.num_piece_types) step.heads.place_type[st] += u;
                    } else {
                        if (pos_idx < brd.num_squares) step.heads.slide_from[pos_idx] += u;
                        const dir: usize = @intCast(lm.flag);
                        if (dir < brd.num_directions) step.heads.slide_dir[dir] += u;

                        const moved: usize = lm.movedStones();
                        const pickup_i = clampPickupToHeadIndex(moved);
                        step.heads.slide_pickup[pickup_i] += u;

                        const ones_u8: u8 = @intCast(@popCount(lm.pattern));
                        if (ones_u8 >= 1 and ones_u8 <= 6) {
                            step.heads.slide_len[ones_u8 - 1] += u;
                        }
                    }
                }
            }

            _ = channels_in;
        }

        try steps.append(allocator.*, step);

        mvs.makeMove(&board, mv);

        board.updateAllVectors();
    }

    const winner = computeWinner(&board);

    std.debug.print("Game finished in {d} plies. Winner: {s}\n", .{
        ply,
        if (winner == null) "Draw" else if (winner.? == .White) "White" else "Black",
    });

    return .{
        .steps = try steps.toOwnedSlice(allocator.*),
        .winner = winner,
    };
}

pub fn writeSelfPlayDataset(
    allocator: *std.mem.Allocator,
    tree_search: *mcts.MonteCarloTreeSearch,
    out_path: []const u8,
    num_games: usize,
    max_plies: usize,
) !void {
    var tmp = brd.Board.init();
    tmp.updateAllVectors();
    const src = tmp.white_vector.data;
    if (src.len % brd.num_squares != 0) return error.BadVectorLength;
    const channels_in: u32 = @intCast(src.len / brd.num_squares);

    var file = try std.fs.cwd().createFile(out_path, .{});
    defer file.close();

    // Use the newer buffered writer API (same style as tei.zig).
    var out_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&out_buffer);
    const w = &file_writer.interface;

    try writeHeader(w, channels_in);

    var written: usize = 0;

    for (0..num_games) |i| {
        std.debug.print("Playing game {d}/{d}\n", .{ i, num_games });
        const gd = try playSelfGameBuffered(allocator, tree_search, max_plies);
        defer freeBufferedSteps(allocator.*, gd.steps);

        for (gd.steps) |s| {
            const z = outcomeZFromWinner(s.to_move, gd.winner);

            try writeRecord(
                w,
                channels_in,
                s.features,
                &s.heads,
                z,
            );

            written += 1;
            if (written % 1024 == 0) try w.flush();
        }
    }

    try w.flush();
    std.debug.print("Wrote {d} records to {s}\n", .{ written, out_path });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    //   selfplay <model.onnx> [out_path] [num_games] [max_plies]
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print(
            "Usage: {s} <model.onnx> [out_path] [num_games] [max_plies]\n",
            .{args[0]},
        );
        return error.MissingModelPath;
    }

    const model_path = args[1];
    const out_path: []const u8 = if (args.len >= 3) args[2] else "selfplay.takbin";
    const num_games: usize = if (args.len >= 4) try std.fmt.parseInt(usize, args[3], 10) else 1000;
    const max_plies: usize = if (args.len >= 5) try std.fmt.parseInt(usize, args[4], 10) else 256;

    const EvalNN = struct {
        fn evalThunk(ctx: *anyopaque, board: *const brd.Board, moves: []const brd.Move, priors_out: []f32) f32 {
            const nne: *nn.NNEval = @ptrCast(@alignCast(ctx));
            return nne.eval(board, moves, priors_out);
        }
    };

    var alloc_copy = allocator;
    var nn_eval = try nn.NNEval.init(alloc_copy, model_path);
    defer nn_eval.deinit();

    var ts = try mcts.MonteCarloTreeSearch.init(&alloc_copy, &nn_eval, EvalNN.evalThunk, false, true);
    defer ts.deinit();

    try writeSelfPlayDataset(&alloc_copy, &ts, out_path, num_games, max_plies);
}

