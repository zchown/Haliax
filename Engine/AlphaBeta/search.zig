const std = @import("std");
const brd = @import("board");
const zob = @import("zobrist");
const tracy = @import("tracy");
const mvs = @import("moves");
const eval = @import("evaluate");
const ptn = @import("ptn");
const tt = @import("transposition");

pub const max_ply: usize = 128;
pub const max_game_ply: usize = 1024;

pub const mate_score: i32 = 888888;
pub const mate_threshold: i32 = mate_score - 256;

// A drop with flag = 3 is not a possible move, so we can use it as a sentinel for "no move"
// A full 0 would be a flat placement at a1
const null_move = brd.Move{ .position = 0, .flag = 3, .pattern = 0 };

pub var nmp_base: usize = 3;
pub var nmp_depth_div: usize = 4;

pub var rfp_margin: i32 = 100;

const lmp_counts = [_]usize{ 0, 8, 12, 16, 24 }; // index = depth

pub var history_div: i32 = 8;

const SCORE_HASH: i32 = 1_000_000;
const SCORE_KILLER_0: i32 = 900_000;
const SCORE_KILLER_1: i32 = 800_000;
const SCORE_COUNTERMOVE: i32 = 100_0000;

pub const NodeType = enum(u2) {
    Root,
    PV,
    NonPV,
};

pub const SearchResult = struct {
    move: brd.Move,
    score: i32,
    depth: usize,
    nodes: u64,
    time_ms: u64,
    pv: [max_ply]brd.Move,
    pv_length: usize,
};

pub const Searcher = struct {
    min_depth: usize = 1,
    max_ms: u64 = 0,
    ideal_ms: u64 = 0,
    force_think: bool = false,
    search_depth: usize = 0,
    timer: std.time.Timer = undefined,
    soft_max_nodes: ?u64 = null,
    max_nodes: ?u64 = null,
    time_stop: bool = false,
    time_offset: u64 = 0,

    nodes: u64 = 0,
    ply: usize = 0,
    seldepth: usize = 0,
    stop: bool = false,
    is_searching: bool = false,

    best_move: brd.Move = null_move,
    best_move_score: i32 = 0,

    pv: [max_ply][max_ply]brd.Move = undefined,
    pv_length: [max_ply]usize = undefined,

    move_lists: [max_ply]mvs.MoveList = undefined,
    score_buf: [max_ply][4096]i32 = undefined,

    search_score: i32 = 0,
    perspective: brd.Color = .White,

    eval_history: [max_ply]i32 = undefined,
    move_history: [max_ply]brd.Move = undefined,

    killer_moves: [max_ply][2]brd.Move = undefined,
    history: [2][brd.num_squares][brd.num_squares][brd.max_pickup]i32 = undefined,
    countermoves: [2][brd.num_squares][brd.num_squares][brd.max_pickup]brd.Move = undefined,

    lmr_table: [max_ply][256]i32 = undefined,

    hash_history: [max_game_ply]zob.ZobristHash = undefined,
    place_history: [max_game_ply]bool = undefined,

    thread_id: usize = 0,
    root_board: *brd.Board = undefined,
    silent_output: bool = false,

    tt_table: *tt.TranspositionTable = undefined,

    allocator: std.mem.Allocator = std.heap.page_allocator,

    pub fn initInPlace(self: *Searcher) void {
        self.timer = std.time.Timer.start() catch unreachable;
        self.resetHeuristics(true);

        for (0..max_ply) |i| {
            self.move_lists[i] = mvs.MoveList.init(&self.allocator, 512) catch unreachable;
        }

        for (1..max_ply) |d| {
            for (1..256) |m| {
                const fd: f64 = @floatFromInt(d);
                const fm: f64 = @floatFromInt(m);
                const reduction = 0.5 + @log(fd) * @log(fm) / 3.0;
                // const reduction = 0.75 + @log(fd) * @log(fm) / 2.0;
                // const reduction = 0.25 + @log(fd) * @log(fm) / 3.0;
                self.lmr_table[d][m] = @intFromFloat(reduction);
            }
        }
        self.lmr_table[0] = [_]i32{0} ** 256;
    }

    pub fn deinit(self: *Searcher) void {
        for (0..max_ply) |i| {
            self.move_lists[i].deinit();
        }
    }

    pub fn resetHeuristics(self: *Searcher, total: bool) void {
        for (0..max_ply) |i| {
            self.pv_length[i] = 0;
            self.eval_history[i] = 0;
            self.move_history[i] = null_move;

            self.killer_moves[i][0] = null_move;
            self.killer_moves[i][1] = null_move;

            for (0..max_ply) |j| {
                self.pv[i][j] = null_move;
            }
        }

        for (0..brd.num_squares) |j| {
            for (0..brd.num_squares) |k| {
                for (0..brd.max_pickup) |p| {
                    self.countermoves[0][j][k][p] = null_move;
                    self.countermoves[1][j][k][p] = null_move;
                    if (total) {
                        self.history[0][j][k][p] = 0;
                        self.history[1][j][k][p] = 0;
                    } else {
                        self.history[0][j][k][p] = @divTrunc(self.history[0][j][k][p], history_div);
                        self.history[1][j][k][p] = @divTrunc(self.history[1][j][k][p], history_div);
                    }
                }
            }
        }
    }

    pub inline fn shouldStop(self: *Searcher) bool {
        const thinking = @atomicLoad(bool, &self.force_think, .acquire);
        return self.stop or
            (self.thread_id == 0 and self.search_depth > self.min_depth and
                ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
                    (!thinking and self.timer.read() / std.time.ns_per_ms >= self.max_ms)));
    }

    pub inline fn shouldNotContinue(self: *Searcher) bool {
        const thinking = @atomicLoad(bool, &self.force_think, .acquire);
        return self.stop or
            (self.thread_id == 0 and self.search_depth > self.min_depth and
                ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
                    (!thinking and self.timer.read() / std.time.ns_per_ms >= self.ideal_ms)));
    }

    pub fn iterativeDeepening(self: *Searcher, board: *brd.Board, max_depth: ?u8) !SearchResult {
        self.stop = false;
        self.is_searching = true;
        self.time_stop = false;
        self.time_offset = 0;
        tt.stop_signal.store(false, .release);
        self.resetHeuristics(false);
        self.nodes = 0;
        self.best_move = null_move;
        self.best_move_score = -mate_score;
        self.timer = std.time.Timer.start() catch unreachable;
        self.perspective = board.to_move;
        self.search_score = 0;

        var score: i32 = -mate_score;

        var bm = null_move;
        var best_pv: [max_ply]brd.Move = undefined;
        var best_pv_length: usize = 0;

        var outer_depth: usize = 1;
        const bound: usize = if (max_depth != null) @as(usize, max_depth.?) else max_ply;

        while (outer_depth <= bound) : (outer_depth += 1) {
            self.ply = 0;
            self.seldepth = 0;
            self.search_depth = outer_depth;

            score = self.negamax(board, outer_depth, -mate_score, mate_score, false, .Root);

            if (self.time_stop or self.shouldStop()) {
                self.time_stop = true;
                tt.stop_signal.store(true, .release);
                break;
            }

            bm = self.best_move;
            best_pv = self.pv[0];
            best_pv_length = self.pv_length[0];

            if (!self.silent_output) {
                self.printInfo(self.nodes, score, best_pv[0..best_pv_length]);
            }

            self.search_score = score;

            if (self.shouldNotContinue()) {
                break;
            }
        }

        self.best_move = bm;
        self.is_searching = false;

        self.tt_table.incrementAge();

        return SearchResult{
            .move = self.best_move,
            .score = self.best_move_score,
            .depth = self.search_depth,
            .nodes = self.nodes,
            .time_ms = (self.timer.read() / std.time.ns_per_ms) -| self.time_offset,
            .pv = best_pv,
            .pv_length = best_pv_length,
        };
    }

    pub fn negamax(
        self: *Searcher,
        board: *brd.Board,
        depth_: usize,
        alpha_: i32,
        beta_: i32,
        is_null: bool,
        node_type: NodeType,
    ) i32 {
        var alpha = alpha_;
        var beta = beta_;
        const depth = depth_;

        self.pv_length[self.ply] = 0;

        if (self.nodes & 2047 == 0 and self.shouldStop()) {
            self.time_stop = true;
            tt.stop_signal.store(true, .release);
            return 0;
        }

        self.seldepth = @max(self.seldepth, self.ply);

        const is_root: bool = node_type == .Root;
        const on_pv: bool = node_type != .NonPV;

        // Check for terminal position
        const result = board.checkResult();
        if (result.ongoing == 0) {
            if (result.road == 0 and result.flat == 0 and result.color == 0) {
                return 0;
            }
            const winner: brd.Color = if (result.color == 0) .White else .Black;
            if (winner == board.to_move) {
                return mate_score - @as(i32, @intCast(self.ply));
            } else {
                return -(mate_score - @as(i32, @intCast(self.ply)));
            }
        }

        if (self.ply >= max_ply) {
            return eval.evaluate(board);
        }

        // Leaf node — static eval
        if (depth == 0) {
            return eval.evaluate(board);
            // return self.quiescence(board, alpha, beta, 4);
        }

        // Mate distance pruning
        if (!is_root) {
            const r_alpha = @max(alpha, -mate_score + @as(i32, @intCast(self.ply)));
            const r_beta = @min(beta, mate_score - @as(i32, @intCast(self.ply + 1)));

            if (r_alpha >= r_beta) {
                return r_alpha;
            }
        }

        self.nodes += 1;

        // TT probe
        var hash_move = null_move;
        const entry = self.tt_table.get(board.zobrist_hash);

        if (entry) |e| {
            var tt_eval = e.eval;

            if (tt_eval > mate_threshold) {
                tt_eval -= @as(i32, @intCast(self.ply));
            } else if (tt_eval < -mate_threshold) {
                tt_eval += @as(i32, @intCast(self.ply));
            }

            hash_move = e.move;

            if (is_root) {
                self.best_move = hash_move;
                self.best_move_score = tt_eval;
            }

            // TT cutoff (non-PV only)
            if (!is_null and !on_pv and !is_root and e.depth >= @as(u8, @intCast(depth))) {
                switch (e.flag) {
                    .Exact => return tt_eval,
                    .Under => alpha = @max(alpha, tt_eval),
                    .Over => beta = @min(beta, tt_eval),
                    .None => {},
                }
                if (alpha >= beta) {
                    return tt_eval;
                }
            }
        }

        // Static eval (needed for NMP)
        var static_eval: i32 = undefined;
        if (is_null) {
            static_eval = -self.eval_history[self.ply - 1];
        } else {
            static_eval = eval.evaluate(board);
        }
        self.eval_history[self.ply] = static_eval;

        if (!on_pv and !is_null and depth <= 4 and static_eval - rfp_margin * @as(i32, @intCast(depth)) >= beta) {
            return static_eval;
        }

        // Null move pruning
        if (!on_pv and !is_null and depth >= 3 and static_eval >= beta) {
            const reserves = if (board.to_move == .White)
                board.white_stones_remaining + board.white_capstones_remaining
            else
                board.black_stones_remaining + board.black_capstones_remaining;

            if (reserves >= 3) {
                const r: usize = nmp_base + depth / nmp_depth_div;
                const reduction = @min(r, depth - 1);

                board.to_move = board.to_move.opposite();
                board.zobrist_hash ^= zob.zobrist_turn_hash;

                self.ply += 1;
                self.move_history[self.ply] = null_move;
                const null_score = -self.negamax(board, depth - reduction, -beta, -beta + 1, true, .NonPV);
                self.ply -= 1;

                board.to_move = board.to_move.opposite();
                board.zobrist_hash ^= zob.zobrist_turn_hash;

                if (self.time_stop) return 0;

                if (null_score >= beta) {
                    if (null_score >= mate_threshold) return beta;
                    return null_score;
                }
            }
        }

        // Generate moves
        self.move_lists[self.ply].clear();
        mvs.generateMoves(board, &self.move_lists[self.ply]) catch unreachable;

        const move_count = self.move_lists[self.ply].count;
        if (move_count == 0) return 0;

        // Score moves
        self.scoreMoves(board, hash_move);

        var best_score: i32 = -mate_score;
        var best_local_move: brd.Move = self.move_lists[self.ply].moves[0];
        var moves_searched: usize = 0;
        var tt_bound: tt.EstimationType = .Over;

        var i: usize = 0;
        while (i < move_count) : (i += 1) {
            self.pickMove(i);

            const move = self.move_lists[self.ply].moves[i];

            if (!on_pv and !is_root and depth <= 4 and moves_searched >= lmp_counts[depth] and best_score > -mate_threshold) {
                // i += 1;
                break;
            }

            mvs.makeMove(board, move);
            self.ply += 1;

            // Repetition detection
            if (move.pattern != 0 and self.isRepetition(board)) {
                self.ply -= 1;
                mvs.undoMove(board, move);
                if (0 > best_score) {
                    best_score = 0;
                    best_local_move = move;
                }
                moves_searched += 1;
                continue;
            }
            self.hash_history[board.half_move_count] = board.zobrist_hash;
            self.place_history[board.half_move_count] = move.pattern != 0;
            self.move_history[self.ply] = move;

            self.tt_table.prefetch(board.zobrist_hash);

            var score: i32 = undefined;

            if (on_pv and moves_searched == 0) {
                score = -self.negamax(board, depth - 1, -beta, -alpha, false, .PV);
            } else {
                var reduction: i32 = 0;

                const is_killer = brd.movesEqual(move, self.killer_moves[self.ply][0]) or brd.movesEqual(move, self.killer_moves[self.ply][1]);

                const can_reduce = depth >= 3 and moves_searched >= 2 and !is_null and !is_killer;

                if (can_reduce) {
                    const d_idx = @min(depth, max_ply - 1);
                    const m_idx = @min(moves_searched, 255);
                    reduction = self.lmr_table[d_idx][m_idx];

                    if (!on_pv) reduction += 1;

                    const color_idx: usize = @intFromEnum(board.to_move.opposite());
                    const from_sq: usize = @intCast(move.position);
                    const to_sq: usize = moveToSq(move);
                    const pk_idx: usize = movePickupIdx(move);
                    if (self.history[color_idx][from_sq][to_sq][pk_idx] > 0) {
                        reduction -= 1;
                    }

                    if (node_type == .NonPV) reduction += 1;

                    // Never reduce into zero or negative depth
                    reduction = @max(0, @min(reduction, @as(i32, @intCast(depth)) - 2));
                }

                const reduced_depth = depth - 1 - @as(usize, @intCast(reduction));

                // Null window search at reduced depth
                score = -self.negamax(board, reduced_depth, -alpha - 1, -alpha, false, .NonPV);

                // If reduced search beat alpha, re-search at full depth (no reduction)
                if (score > alpha and reduction > 0) {
                    score = -self.negamax(board, depth - 1, -alpha - 1, -alpha, false, .NonPV);
                }

                // Re-search with full window if it improved alpha on a PV node
                if (on_pv and score > alpha and score < beta) {
                    score = -self.negamax(board, depth - 1, -beta, -alpha, false, .PV);
                }
            }

            self.ply -= 1;
            mvs.undoMove(board, move);

            if (self.time_stop) return 0;

            if (score > best_score) {
                best_score = score;
                best_local_move = move;

                // Update PV
                self.pv[self.ply][0] = move;
                const child_len = self.pv_length[self.ply + 1];
                if (child_len > 0) {
                    @memcpy(
                        self.pv[self.ply][1 .. 1 + child_len],
                        self.pv[self.ply + 1][0..child_len],
                    );
                }
                self.pv_length[self.ply] = 1 + child_len;

                if (score > alpha) {
                    alpha = score;
                    tt_bound = .Exact;

                    if (is_root) {
                        self.best_move = move;
                        self.best_move_score = score;
                    }

                    if (score >= beta) {
                        if (!brd.movesEqual(self.killer_moves[self.ply][0], move)) {
                            self.killer_moves[self.ply][1] = self.killer_moves[self.ply][0];
                            self.killer_moves[self.ply][0] = move;
                        }

                        // History: reward cutoff move, penalise earlier moves
                        self.updateHistory(board, move, depth, true);
                        self.updateCountermove(board, move);
                        var j: usize = 0;
                        while (j < move_count) : (j += 1) {
                            const failed_move = self.move_lists[self.ply].moves[j];
                            if (brd.movesEqual(failed_move, move)) break;
                            self.updateHistory(board, failed_move, depth, false);
                        }

                        tt_bound = .Under;
                        break;
                    }
                }
            }

            moves_searched += 1;
        }

        // Store in TT
        var store_eval = best_score;
        if (store_eval > mate_threshold) {
            store_eval += @as(i32, @intCast(self.ply));
        } else if (store_eval < -mate_threshold) {
            store_eval -= @as(i32, @intCast(self.ply));
        }

        self.tt_table.set(tt.Entry{
            .hash = board.zobrist_hash,
            .eval = store_eval,
            .move = best_local_move,
            .flag = tt_bound,
            .depth = @intCast(depth),
        });

        return best_score;
    }

    fn scoreMoves(self: *Searcher, board: *brd.Board, hash_move: brd.Move) void {
        const move_list = &self.move_lists[self.ply];
        const count = move_list.count;
        const color_idx: usize = @intFromEnum(board.to_move);

        // Countermove lookup: what's a good response to the opponent's last move?
        var cm = null_move;
        if (self.ply > 0) {
            const prev = self.move_history[self.ply];
            if (!brd.isNullMove(prev)) {
                const prev_from: usize = @intCast(prev.position);
                const prev_to: usize = moveToSq(prev);
                const prev_pickup: usize = movePickupIdx(prev);
                cm = self.countermoves[color_idx][prev_from][prev_to][prev_pickup];
            }
        }

        for (0..count) |idx| {
            const m = move_list.moves[idx];
            var score: i32 = 0;

            if (brd.movesEqual(m, hash_move) and !brd.isNullMove(hash_move)) {
                score = SCORE_HASH;
            } else if (brd.movesEqual(m, self.killer_moves[self.ply][0])) {
                score = SCORE_KILLER_0;
            } else if (brd.movesEqual(m, self.killer_moves[self.ply][1])) {
                score = SCORE_KILLER_1;
            } else if (!brd.isNullMove(cm) and brd.movesEqual(m, cm)) {
                const from_sq: usize = @intCast(m.position);
                const to_sq: usize = moveToSq(m);
                const pickup_idx: usize = movePickupIdx(m);
                score = self.history[color_idx][from_sq][to_sq][pickup_idx] + SCORE_COUNTERMOVE;
            } else {
                const from_sq: usize = @intCast(m.position);
                const to_sq: usize = moveToSq(m);
                const pickup_idx: usize = movePickupIdx(m);
                score = self.history[color_idx][from_sq][to_sq][pickup_idx];
            }

            self.score_buf[self.ply][idx] = score;
        }
    }

    fn pickMove(self: *Searcher, start: usize) void {
        const count = self.move_lists[self.ply].count;
        var best_idx = start;
        var best_score = self.score_buf[self.ply][start];

        var ii = start + 1;
        while (ii < count) : (ii += 1) {
            if (self.score_buf[self.ply][ii] > best_score) {
                best_score = self.score_buf[self.ply][ii];
                best_idx = ii;
            }
        }

        if (best_idx != start) {
            const tmp_move = self.move_lists[self.ply].moves[start];
            self.move_lists[self.ply].moves[start] = self.move_lists[self.ply].moves[best_idx];
            self.move_lists[self.ply].moves[best_idx] = tmp_move;

            const tmp_score = self.score_buf[self.ply][start];
            self.score_buf[self.ply][start] = self.score_buf[self.ply][best_idx];
            self.score_buf[self.ply][best_idx] = tmp_score;
        }
    }

    fn updateHistory(self: *Searcher, board: *brd.Board, move: brd.Move, depth: usize, good: bool) void {
        const from_sq: usize = @intCast(move.position);
        const to_sq: usize = moveToSq(move);
        const pickup_idx: usize = movePickupIdx(move);
        const color_idx: usize = @intFromEnum(board.to_move);

        const bonus: i32 = @as(i32, @intCast(depth)) * @as(i32, @intCast(depth));
        const delta: i32 = if (good) bonus else -bonus;

        const current = self.history[color_idx][from_sq][to_sq][pickup_idx];
        self.history[color_idx][from_sq][to_sq][pickup_idx] =
            current + delta - @divTrunc(current * @as(i32, @intCast(@abs(delta))), 16384);
    }

    fn updateCountermove(self: *Searcher, board: *brd.Board, move: brd.Move) void {
        if (self.ply == 0) return;
        const prev = self.move_history[self.ply];
        if (brd.isNullMove(prev)) return;
        const prev_from: usize = @intCast(prev.position);
        const prev_to: usize = moveToSq(prev);
        const prev_pickup: usize = movePickupIdx(prev);
        const color_idx: usize = @intFromEnum(board.to_move);
        self.countermoves[color_idx][prev_from][prev_to][prev_pickup] = move;
    }

    pub fn printInfo(self: *Searcher, total_nodes: u64, score: i32, pv_slice: []const brd.Move) void {
        const elapsed_ms = self.timer.read() / std.time.ns_per_ms;
        const nps = if (elapsed_ms > 0) total_nodes * 1000 / elapsed_ms else 0;

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        stdout.print("info depth {d} seldepth {d} score cp {d} nodes {d} nps {d} time {d} hashfull {d}", .{
            self.search_depth,
            self.seldepth,
            score,
            total_nodes,
            nps,
            elapsed_ms,
            self.tt_table.getFillPermill(),
        }) catch return;

        if (pv_slice.len > 0) {
            stdout.print(" pv", .{}) catch return;
            for (pv_slice) |move| {
                if (brd.isNullMove(move)) break;
                var buf: [16]u8 = undefined;
                const mv_str = moveToStringBuf(move, &buf);
                stdout.print(" {s}", .{mv_str}) catch return;
            }
        }

        stdout.print("\n", .{}) catch return;
        stdout.flush() catch return;
    }

    fn isRepetition(self: *Searcher, board: *brd.Board) bool {
        var i = board.half_move_count - 2;
        while (i >= 0) : (i -= 1) {
            if (!self.place_history[i]) {
                break;
            }

            i -= 1;

            if (board.zobrist_hash == self.hash_history[i]) {
                return true;
            }
        }
        return false;
    }
};

fn moveToSq(move: brd.Move) usize {
    if (move.pattern != 0) {
        const dir: brd.Direction = @enumFromInt(move.flag);
        const len = @popCount(move.pattern);
        const end_pos = brd.nthPositionFrom(move.position, dir, len) orelse move.position;
        return @as(usize, end_pos);
    } else {
        return @as(usize, @intCast(move.position));
    }
}

fn movePickupIdx(move: brd.Move) usize {
    if (move.pattern != 0) {
        return @popCount(move.pattern);
    } else {
        return switch (@as(brd.StoneType, @enumFromInt(move.flag))) {
            .Flat => 0,
            .Capstone => 1,
            .Standing => 2,
        };
    }
}

fn moveToStringBuf(move: brd.Move, buf: []u8) []const u8 {
    const col_char: u8 = 'a' + @as(u8, @intCast(brd.getX(move.position)));
    const row_char: u8 = '1' + @as(u8, @intCast(brd.getY(move.position)));
    var idx: usize = 0;

    if (move.pattern == 0) {
        const stone_type: brd.StoneType = @enumFromInt(move.flag);
        switch (stone_type) {
            .Flat => {},
            .Standing => {
                buf[idx] = 'S';
                idx += 1;
            },
            .Capstone => {
                buf[idx] = 'C';
                idx += 1;
            },
        }
        buf[idx] = col_char;
        idx += 1;
        buf[idx] = row_char;
        idx += 1;
    } else {
        const count = @popCount(move.pattern);
        buf[idx] = '0' + @as(u8, @intCast(count));
        idx += 1;
        buf[idx] = col_char;
        idx += 1;
        buf[idx] = row_char;
        idx += 1;

        const dir: brd.Direction = @enumFromInt(move.flag);
        buf[idx] = switch (dir) {
            .North => '+',
            .South => '-',
            .East => '>',
            .West => '<',
        };
        idx += 1;

        var started = false;
        var drops: [8]u8 = undefined;
        var num_drops: usize = 0;
        var cur_drop: u8 = 0;

        for (0..8) |bi| {
            const bit = (move.pattern >> @as(u3, @intCast(7 - bi))) & 0x1;
            if (!started) {
                if (bit == 1) {
                    started = true;
                    cur_drop = 0;
                } else continue;
            }
            if (bit == 1 and num_drops > 0) {
                drops[num_drops - 1] = cur_drop;
                cur_drop = 0;
                num_drops += 1;
            } else if (bit == 1 and num_drops == 0) {
                num_drops = 1;
                cur_drop = 0;
            }
            cur_drop += 1;
        }
        if (num_drops > 0) {
            drops[num_drops - 1] = cur_drop;
        }

        if (count > 1) {
            for (0..num_drops) |di| {
                buf[idx] = '0' + drops[di];
                idx += 1;
            }
        }
    }

    return buf[0..idx];
}

pub fn calculateTimeAllocation(
    wtime_ms: ?u64,
    btime_ms: ?u64,
    winc_ms: ?u64,
    binc_ms: ?u64,
    movetime_ms: ?u64,
    side_to_move: brd.Color,
) struct { max_ms: u64, ideal_ms: u64 } {
    const overhead: u64 = 30;

    if (movetime_ms) |mt| {
        return .{ .max_ms = mt, .ideal_ms = mt };
    }

    const our_time = if (side_to_move == .White) wtime_ms else btime_ms;
    const our_inc = if (side_to_move == .White) winc_ms else binc_ms;

    if (our_time) |time| {
        const safe_time = time -| overhead;
        const increment = our_inc orelse 0;
        const moves_remaining: u64 = 30;
        const total_time = safe_time + (increment * (moves_remaining - 1));
        const base_time = total_time / moves_remaining;
        const ideal_ms = @min(base_time * 9 / 10, safe_time -| 50);
        const max_ms = @min(ideal_ms * 3, safe_time * 4 / 10);
        return .{
            .max_ms = @max(max_ms, 1),
            .ideal_ms = @max(ideal_ms, 1),
        };
    }

    return .{ .max_ms = 5000, .ideal_ms = 5000 };
}
