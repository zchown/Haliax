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

pub var aspiration_window: i32 = 50;

pub var rfp_depth: i32 = 6;
pub var rfp_mul: i32 = 75;

pub var nmp_base: usize = 3;
pub var nmp_depth_div: usize = 4;

pub var quiet_lmr: [max_ply][256]i32 = undefined;

pub var futility_mul: i32 = 100;

pub var iir_depth: usize = 4;

pub var se_depth: usize = 6;
pub var se_margin_mul: i32 = 2;
pub var se_double_margin: i32 = 100;
pub var se_triple_margin: i32 = 200;
pub var max_double_extensions: i32 = 6;

pub var lmr_pv_min: usize = 8;
pub var lmr_non_pv_min: usize = 4;

pub var history_lmr_div: i32 = 8192;

pub var history_div: i32 = 4;

// Minimum remaining depth to enable expensive road-aware move scoring.
// At depths below this, we skip UF lookups in scoreMoves entirely.
pub var road_min_depth: usize = 3;

const null_move = brd.Move{ .position = 0, .flag = 0, .pattern = 0 };

const SCORE_HASH: i32 = 1_000_000;
const SCORE_ROAD_WIN: i32 = 960_000; 
const SCORE_ROAD_BLOCK: i32 = 950_000; 
const SCORE_KILLER_0: i32 = 900_000;
const SCORE_KILLER_1: i32 = 800_000;
const SCORE_COUNTERMOVE: i32 = 700_000;
const SCORE_CRUSH: i32 = 500_000; 
const SCORE_SLIDE_ROAD_WIN: i32 = 480_000; 
const SCORE_SLIDE_ROAD_BLOCK: i32 = 470_000; 
const SCORE_ROAD_EXTEND: i32 = 5_000; 

pub fn initQuietLMR() [max_ply][256]i32 {
    var table: [max_ply][256]i32 = undefined;
    for (0..max_ply) |d| {
        for (0..256) |m| {
            if (d == 0 or m == 0) {
                table[d][m] = 0;
            } else {
                const fd: f64 = @floatFromInt(d);
                const fm: f64 = @floatFromInt(m);
                const val: f64 = 0.75 + @log(fd) * @log(fm) / 2.25;
                table[d][m] = @intFromFloat(@max(val, 0));
            }
        }
    }
    return table;
}

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

inline fn ufRoot(parent: *const [brd.num_squares]usize, i: usize) usize {
    var x = i;
    while (x != parent[x]) {
        x = parent[x];
    }
    return x;
}

/// Compute the edge bitmask for a board position.
///   bit 0 = north (top row), bit 1 = south (bottom row),
///   bit 2 = east  (right col), bit 3 = west  (left col)
inline fn edgeBits(sq: usize) u4 {
    const row = sq / brd.board_size;
    const col = sq % brd.board_size;
    var mask: u4 = 0;
    if (row == brd.board_size - 1) mask |= 0b0001; // north
    if (row == 0) mask |= 0b0010; // south
    if (col == brd.board_size - 1) mask |= 0b0100; // east
    if (col == 0) mask |= 0b1000; // west
    return mask;
}

inline fn spansVertical(edges: u4) bool {
    return (edges & 0b0011) == 0b0011;
}

inline fn spansHorizontal(edges: u4) bool {
    return (edges & 0b1100) == 0b1100;
}

inline fn spansAny(edges: u4) bool {
    return spansVertical(edges) or spansHorizontal(edges);
}

/// Compute a bitboard of empty squares where placing a flat/cap for
/// `color` would complete a road (connecting adjacent groups that
/// together span opposite edges).
fn computeRoadThreatSquares(board_ptr: *brd.Board, color: brd.Color) brd.Bitboard {
    if (!brd.do_road_uf) return 0;

    const uf = if (color == .White) &board_ptr.white_road_uf else &board_ptr.black_road_uf;
    var threats: brd.Bitboard = 0;

    var empty = board_ptr.empty_squares;
    while (empty != 0) {
        const pos = brd.getLSB(empty);
        brd.clearBit(&empty, pos);
        const sq_idx: usize = @intCast(pos);

        var combined: u4 = edgeBits(sq_idx);

        const neighbours = [_]?brd.Position{
            brd.nextPosition(pos, .North),
            brd.nextPosition(pos, .South),
            brd.nextPosition(pos, .East),
            brd.nextPosition(pos, .West),
        };

        for (neighbours) |maybe_nxt| {
            if (maybe_nxt) |nxt| {
                const nsq: usize = @intCast(nxt);
                if (uf.active[nsq]) {
                    const root = ufRoot(&uf.parent, nsq);
                    combined |= @as(u4, @bitCast(uf.edges[root]));
                }
            }
        }

        if (spansAny(combined)) {
            brd.setBit(&threats, pos);
        }
    }

    return threats;
}

inline fn slideDestPos(move: brd.Move) ?brd.Position {
    const dir: brd.Direction = @enumFromInt(move.flag);
    const len = @popCount(move.pattern);
    return brd.nthPositionFrom(move.position, dir, len);
}

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
    score_lists: [max_ply][]i32 = undefined,
    score_buf: [max_ply][4096]i32 = undefined,
    score_counts: [max_ply]usize = undefined,

    search_score: i32 = 0,
    perspective: brd.Color = .White,

    eval_history: [max_ply]i32 = undefined,
    move_history: [max_ply]brd.Move = undefined,
    killer_moves: [max_ply][2]brd.Move = undefined,
    countermoves: [2][brd.num_squares][brd.num_squares][brd.max_pickup]brd.Move = undefined,
    history: [2][brd.num_squares][brd.num_squares][brd.max_pickup]i32 = undefined,
    excluded_moves: [max_ply]brd.Move = undefined,
    double_extensions: [max_ply]i32 = undefined,
    correction: [2][16384]i32 = undefined,

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
            self.score_counts[i] = 0;
        }
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
            self.excluded_moves[i] = null_move;
            self.double_extensions[i] = 0;

            self.killer_moves[i][0] = null_move;
            self.killer_moves[i][1] = null_move;

            for (0..max_ply) |j| {
                self.pv[i][j] = null_move;
            }
        }

        for (0..2) |c| {
            if (total) {
                @memset(&self.correction[c], 0);
            } else {
                for (&self.correction[c]) |*entry| {
                    entry.* = @divTrunc(entry.*, history_div);
                }
            }
        }

        for (0..brd.num_squares) |j| {
            for (0..brd.num_squares) |k| {
                for (0..brd.max_pickup) |p| {
                    if (total) {
                        self.history[0][j][k][p] = 0;
                        self.history[1][j][k][p] = 0;
                        self.countermoves[0][j][k][p] = null_move;
                        self.countermoves[1][j][k][p] = null_move;
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

    pub inline fn shouldNotContinue(self: *Searcher, factor: f32) bool {
        const thinking = @atomicLoad(bool, &self.force_think, .acquire);
        const effective_ideal: u64 = @intFromFloat(@as(f32, @floatFromInt(self.ideal_ms)) * factor);
        return self.stop or
    (self.thread_id == 0 and self.search_depth > self.min_depth and
    ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
    (!thinking and self.timer.read() / std.time.ns_per_ms >= @min(self.ideal_ms, effective_ideal))));
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

        var prev_score: i32 = -mate_score;
        var score: i32 = -mate_score;

        var bm = null_move;
        var best_pv: [max_ply]brd.Move = undefined;
        var best_pv_length: usize = 0;

        var stability: usize = 0;

        var outer_depth: usize = 1;
        const bound: usize = if (max_depth != null) @as(usize, max_depth.?) else max_ply;

        outer: while (outer_depth <= bound) : (outer_depth += 1) {
            self.ply = 0;
            self.seldepth = 0;
            self.search_depth = outer_depth;

            var alpha = if (outer_depth > 1) prev_score - aspiration_window else -mate_score;
            var beta = if (outer_depth > 1) prev_score + aspiration_window else mate_score;
            var delta: i32 = aspiration_window;

            const depth = outer_depth;
            var window_failed = false;

            while (true) {
                score = self.negamax(board, depth, alpha, beta, false, if (depth == outer_depth) NodeType.Root else NodeType.PV, false);

                if (self.time_stop or self.shouldStop()) {
                    self.time_stop = true;
                    tt.stop_signal.store(true, .release);
                    break :outer;
                }

                if (score <= alpha) {
                    beta = @divTrunc(alpha + beta, 2);
                    alpha = @max(alpha - delta, -mate_score);
                    delta = @min(delta * 2, mate_score);
                    window_failed = false;
                } else if (score >= beta) {
                    beta = @min(beta + delta, mate_score);
                    delta = @min(delta * 2, mate_score);
                    window_failed = true;
                } else {
                    window_failed = false;
                    break;
                }
            }

            if (!brd.movesEqual(self.best_move, bm)) {
                stability = 0;
            } else {
                stability += 1;
            }

            if (!window_failed) {
                bm = self.best_move;
                best_pv = self.pv[0];
                best_pv_length = self.pv_length[0];
            }

            if (!self.silent_output) {
                self.printInfo(self.nodes, score, best_pv[0..best_pv_length]);
            }

            var factor: f32 = @max(0.65, 1.3 - 0.03 * @as(f32, @floatFromInt(stability)));

            if (stability == 0) {
                factor = @min(factor * 1.2, 1.5);
            }

            if (score - prev_score > aspiration_window) {
                factor *= 1.3;
            } else if (prev_score - score > aspiration_window) {
                factor *= 1.5;
            }

            prev_score = score;
            self.search_score = score;

            if (self.shouldNotContinue(factor)) {
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
    cutnode: bool,
) i32 {
        var alpha = alpha_;
        var beta = beta_;
        const depth = depth_;

        const corr_idx: usize = @as(usize, @truncate(board.zobrist_hash)) & 16383;
        const color_idx: usize = @intFromEnum(board.to_move);

        self.pv_length[self.ply] = 0;

        if (self.nodes & 2047 == 0 and self.shouldStop()) {
            self.time_stop = true;
            tt.stop_signal.store(true, .release);
            return 0;
        }

        self.seldepth = @max(self.seldepth, self.ply);

        const is_root: bool = node_type == .Root;
        const on_pv: bool = node_type != .NonPV;

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

        if (self.ply >= max_ply or depth == 0) {
            return eval.evaluate(board);
        }

        if (!is_root) {
            const r_alpha = @max(alpha, -mate_score + @as(i32, @intCast(self.ply)));
            const r_beta = @min(beta, mate_score - @as(i32, @intCast(self.ply + 1)));

            if (r_alpha >= r_beta) {
                return r_alpha;
            }
        }

        self.nodes += 1;

        var hash_move = null_move;
        var tt_hit = false;
        var tt_eval: i32 = 0;
        var tt_flag: tt.EstimationType = .None;
        var tt_depth: usize = 0;
        const entry = self.tt_table.get(board.zobrist_hash);

        if (entry) |e| {
            tt_hit = true;
            tt_eval = e.eval;
            tt_depth = @as(usize, e.depth);
            tt_flag = e.flag;

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

        var static_eval: i32 = undefined;
        if (tt_hit) {
            static_eval = tt_eval;
        } else if (is_null) {
            static_eval = -self.eval_history[self.ply - 1];
        } else {
            static_eval = eval.evaluate(board);
            static_eval += @divTrunc(self.correction[color_idx][corr_idx], 256);
        }

        self.eval_history[self.ply] = static_eval;

        const improving: bool = self.ply >= 2 and static_eval > self.eval_history[self.ply - 2];

        var effective_depth = depth;
        if (depth >= iir_depth and !tt_hit and brd.isNullMove(self.excluded_moves[self.ply])) {
            effective_depth -= 1;
        }

        if (!on_pv and !is_null and depth <= @as(usize, @intCast(rfp_depth))) {
            const margin = rfp_mul * @as(i32, @intCast(depth)) - @as(i32, if (improving) rfp_mul else 0);
            if (static_eval - margin >= beta) {
                return static_eval;
            }
        }

        if (!on_pv and !is_null and depth >= 3 and static_eval >= beta and cutnode) {
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
                self.double_extensions[self.ply] = self.double_extensions[self.ply - 1];
                const null_score = -self.negamax(board, depth - reduction, -beta, -beta + 1, true, .NonPV, !cutnode);
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

        self.move_lists[self.ply].clear();
        mvs.generateMoves(board, &self.move_lists[self.ply]) catch unreachable;

        const move_count = self.move_lists[self.ply].count;

        if (move_count == 0) {
            return 0;
        }

        self.scoreMoves(board, hash_move);

        var best_score: i32 = -mate_score;
        var best_local_move: brd.Move = self.move_lists[self.ply].moves[0];
        var moves_searched: usize = 0;
        var tt_bound: tt.EstimationType = .Over;

        const excluded_move = self.excluded_moves[self.ply];
        const can_singular = !is_root and effective_depth >= se_depth and tt_hit and
            tt_depth >= effective_depth - 3 and (tt_flag == .Under or tt_flag == .Exact) and
            !brd.isNullMove(hash_move) and brd.isNullMove(excluded_move) and
            @abs(tt_eval) < mate_threshold;

        var i: usize = 0;
        while (i < move_count) : (i += 1) {
            self.pickMove(i);

            const move = self.move_lists[self.ply].moves[i];
            const move_score = self.score_buf[self.ply][i];

            if (!brd.isNullMove(excluded_move) and brd.movesEqual(move, excluded_move)) {
                continue;
            }

            const is_crush = (move.pattern != 0) and
                (board.crushMoves[(board.half_move_count - 1) % brd.crush_map_size] == .Crush);

            const is_road_critical: bool = (move_score == SCORE_ROAD_WIN or move_score == SCORE_ROAD_BLOCK);

            if (!on_pv and effective_depth <= 3 and moves_searched > 0 and
                !is_road_critical and !is_crush)
            {
                const fut_margin = static_eval + futility_mul * @as(i32, @intCast(effective_depth));
                if (fut_margin <= alpha and best_score > -mate_threshold) {
                    continue;
                }
            }

            var extension: i32 = 0;

            if (is_crush) {
                extension = 1;
            }

            if (extension == 0 and is_road_critical) {
                extension = 1;
            }

            // Singular extensions
            if (can_singular and brd.movesEqual(move, hash_move)) {
                const se_beta = tt_eval - se_margin_mul * @as(i32, @intCast(effective_depth));
                const se_depth_val = @max((effective_depth - 1) / 2, 1);

                self.excluded_moves[self.ply] = move;
                const se_score = self.negamax(board, se_depth_val, se_beta - 1, se_beta, false, .NonPV, cutnode);
                self.excluded_moves[self.ply] = null_move;

                if (self.time_stop) return 0;

                if (se_score < se_beta) {
                    extension = 1;

                    if (!on_pv and self.double_extensions[self.ply] < max_double_extensions) {
                        if (se_score < se_beta - se_triple_margin) {
                            extension = 3;
                        } else if (se_score < se_beta - se_double_margin) {
                            extension = 2;
                        }
                    }
                } else if (se_beta >= beta) {
                    return se_beta;
                }
                else if (tt_eval >= beta) {
                    extension = -1;
                } else if (cutnode) {
                    extension = -1;
                }
            }

            mvs.makeMove(board, move);
            self.ply += 1;
            self.move_history[self.ply] = move;

            self.double_extensions[self.ply] = self.double_extensions[self.ply - 1] +
                @as(i32, if (extension > 1) extension - 1 else 0);

            self.tt_table.prefetch(board.zobrist_hash);

            const new_depth: usize = @intCast(@max(
                @as(i32, @intCast(effective_depth)) - 1 + extension,
                0,
            ));
            var score: i32 = undefined;

            const min_lmr_move: usize = if (on_pv) lmr_pv_min else lmr_non_pv_min;
            var do_full_search = false;

            if (on_pv and moves_searched == 0) {
                score = -self.negamax(board, new_depth, -beta, -alpha, false, .PV, false);
            } else {
                if (effective_depth >= 3 and moves_searched >= min_lmr_move) {
                    var r: i32 = quiet_lmr[@min(effective_depth, max_ply - 1)][@min(moves_searched, 255)];

                    if (improving) r -= 1;

                    if (move_score > 1000) r -= 1;

                    if (cutnode) r += 1;

                    if (!on_pv) r += 1;

                    r -= @divTrunc(move_score, history_lmr_div);

                    // Reduce less for road-critical and crush moves
                    if (is_road_critical or is_crush) r -= 2;

                    const reduced_depth: usize = @intCast(
                        std.math.clamp(
                            @as(i32, @intCast(new_depth)) - r,
                            1,
                            @as(i32, @intCast(new_depth + 1)),
                        ),
                    );

                    score = -self.negamax(board, reduced_depth, -alpha - 1, -alpha, false, .NonPV, true);

                    do_full_search = score > alpha and reduced_depth < new_depth;
                } else {
                    do_full_search = !on_pv or moves_searched > 0;
                }

                if (do_full_search) {
                    score = -self.negamax(board, new_depth, -alpha - 1, -alpha, false, .NonPV, !cutnode);
                }

                if (on_pv and ((score > alpha and score < beta) or moves_searched == 0)) {
                    score = -self.negamax(board, new_depth, -beta, -alpha, false, .PV, false);
                }
            }

            self.ply -= 1;
            mvs.undoMove(board, move);

            if (self.time_stop) return 0;

            if (score > best_score) {
                best_score = score;
                best_local_move = move;

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
                        tt_bound = .Under;
                        break;
                    }
                }
            }

            moves_searched += 1;
        }

        if (best_score >= beta) {
            if (!brd.movesEqual(self.killer_moves[self.ply][0], best_local_move)) {
                self.killer_moves[self.ply][1] = self.killer_moves[self.ply][0];
                self.killer_moves[self.ply][0] = best_local_move;
            }

            self.updateCountermove(best_local_move);

            self.updateHistory(best_local_move, effective_depth, true);

            var j: usize = 0;
            while (j < move_count) : (j += 1) {
                const failed_move = self.move_lists[self.ply].moves[j];
                if (brd.movesEqual(failed_move, best_local_move)) break;
                self.updateHistory(failed_move, effective_depth, false);
            }
        }

        if (!is_null and !brd.isNullMove(best_local_move) and best_score != 0) {
            const diff = best_score - static_eval;
            const scaled = @divTrunc(diff * 256, @max(@as(i32, @intCast(effective_depth)), 1));
            self.correction[color_idx][corr_idx] =
            @divTrunc(self.correction[color_idx][corr_idx] * 255 + scaled, 256);
        }

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
            .depth = @intCast(effective_depth),
        });

        return best_score;
    }

    fn scoreMoves(self: *Searcher, board: *brd.Board, hash_move: brd.Move) void {
        const move_list = &self.move_lists[self.ply];
        const count = move_list.count;

        // Only pay for expensive road analysis at higher remaining depths
        const remaining = self.search_depth -| self.ply;
        const do_road = brd.do_road_uf and remaining >= road_min_depth;

        var my_threats: brd.Bitboard = 0;
        var opp_threats: brd.Bitboard = 0;
        var road_adj: brd.Bitboard = 0;

        if (do_road) {
            my_threats = computeRoadThreatSquares(board, board.to_move);
            opp_threats = computeRoadThreatSquares(board, board.to_move.opposite());

            const my_roads = (if (board.to_move == .White) board.white_control else board.black_control) & ~board.standing_stones;
            road_adj = computeRoadAdjacentEmpty(my_roads, board.empty_squares);
        }

        // Countermove lookup
        var cm = null_move;
        if (self.ply > 0) {
            const prev = self.move_history[self.ply];
            if (!brd.isNullMove(prev)) {
                const prev_from: usize = @intCast(prev.position);
                const prev_to: usize = moveToSq(prev);
                const opp_color: usize = @intFromEnum(self.perspective.opposite());

                var pickup_idx: usize = 0;
                if (prev.pattern != 0) {
                    pickup_idx = @popCount(prev.pattern);
                } else {
                    switch (@as(brd.StoneType, @enumFromInt(prev.flag))) {
                        .Flat => pickup_idx = 0,
                        .Capstone => pickup_idx = 1,
                        .Standing => pickup_idx = 2,
                    }
                }

                cm = self.countermoves[opp_color][prev_from][prev_to][pickup_idx];
            }
        }

        for (0..count) |idx| {
            const m = move_list.moves[idx];
            var score: i32 = 0;

            if (brd.movesEqual(m, hash_move) and !brd.isNullMove(hash_move)) {
                score = SCORE_HASH;
            }
            else if (m.pattern == 0 and
                m.flag != @intFromEnum(brd.StoneType.Standing) and
                brd.getBit(my_threats, m.position))
            {
                score = SCORE_ROAD_WIN;
            }
            else if (m.pattern == 0 and
                m.flag != @intFromEnum(brd.StoneType.Standing) and
                brd.getBit(opp_threats, m.position))
            {
                score = SCORE_ROAD_BLOCK;
            }
            else if (brd.movesEqual(m, self.killer_moves[self.ply][0])) {
                score = SCORE_KILLER_0;
            } else if (brd.movesEqual(m, self.killer_moves[self.ply][1])) {
                score = SCORE_KILLER_1;
            }
            else if (!brd.isNullMove(cm) and brd.movesEqual(m, cm)) {
                score = SCORE_COUNTERMOVE;
            }
            else {
                const from_sq: usize = @intCast(m.position);
                const to_sq: usize = moveToSq(m);
                const color_idx: usize = @intFromEnum(self.perspective);

                if (m.pattern == 0) {
                    if (m.flag == @intFromEnum(brd.StoneType.Flat)) {
                        score = self.history[color_idx][from_sq][to_sq][0];
                        score += 100;

                        if (brd.getBit(road_adj, m.position)) {
                            score += SCORE_ROAD_EXTEND;
                        }
                    } else if (m.flag == @intFromEnum(brd.StoneType.Capstone)) {
                        score = self.history[color_idx][from_sq][to_sq][1];
                        score += 200;

                        if (brd.getBit(road_adj, m.position)) {
                            score += SCORE_ROAD_EXTEND;
                        }
                    } else {
                        // Standing stone
                        score = self.history[color_idx][from_sq][to_sq][2];
                        // not usually a good idea or it will be in counter / killer tables
                        score -= 10;
                    }
                } else {
                    const pickup: usize = @popCount(m.pattern);
                    score = self.history[color_idx][from_sq][to_sq][pickup];

                    // Stack ownership bonus
                    if (board.to_move == .White) {
                        score += @as(i32, @intCast(board.squares[from_sq].white_count)) * @as(i32, @intCast(pickup));
                    } else {
                        score += @as(i32, @intCast(board.squares[from_sq].black_count)) * @as(i32, @intCast(pickup));
                    }

                    // Crush bonus
                    if (board.crushMoves[(board.half_move_count - 1) % brd.crush_map_size] == .Crush) {
                        score += SCORE_CRUSH;
                    }

                    // Slide road scoring: check destination against threat
                    if (my_threats != 0 or opp_threats != 0) {
                        if (slideDestPos(m)) |dest| {
                            if (brd.getBit(my_threats, dest)) {
                                score += SCORE_SLIDE_ROAD_WIN;
                            } else if (brd.getBit(opp_threats, dest)) {
                                score += SCORE_SLIDE_ROAD_BLOCK;
                            }
                        }
                    }
                }
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

    fn updateHistory(self: *Searcher, move: brd.Move, depth: usize, good: bool) void {
        const from_sq: usize = @intCast(move.position);
        const to_sq: usize = moveToSq(move);

        const color_idx: usize = @intFromEnum(self.perspective);
        const bonus: i32 = @as(i32, @intCast(depth)) * @as(i32, @intCast(depth));
        const delta: i32 = if (good) bonus else -bonus;

        var pickup_idx: usize = 0;
        if (move.pattern != 0) {
            pickup_idx = @popCount(move.pattern);
        } else {
            switch (@as(brd.StoneType, @enumFromInt(move.flag))) {
                .Flat => pickup_idx = 0,
                .Capstone => pickup_idx = 1,
                .Standing => pickup_idx = 2,
            }
        }

        const current = self.history[color_idx][from_sq][to_sq][pickup_idx];
        self.history[color_idx][from_sq][to_sq][pickup_idx] = current + delta - @divTrunc(current * @as(i32, @intCast(@abs(delta))), 16384);
    }

    fn updateCountermove(self: *Searcher, move: brd.Move) void {
        if (self.ply == 0) return;
        const prev = self.move_history[self.ply];
        if (brd.isNullMove(prev)) return;
        const prev_from: usize = @intCast(prev.position);
        const prev_to: usize = moveToSq(prev);
        const opp_color: usize = @intFromEnum(self.perspective.opposite());

        var pickup_idx: usize = 0;
        if (prev.pattern != 0) {
            pickup_idx = @popCount(prev.pattern);
        } else {
            switch (@as(brd.StoneType, @enumFromInt(prev.flag))) {
                .Flat => pickup_idx = 0,
                .Capstone => pickup_idx = 1,
                .Standing => pickup_idx = 2,
            }
        }

        self.countermoves[opp_color][prev_from][prev_to][pickup_idx] = move;
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
};


fn computeRoadAdjacentEmpty(road_bb: brd.Bitboard, empty: brd.Bitboard) brd.Bitboard {
    var dilated: brd.Bitboard = road_bb;
    dilated |= (road_bb << brd.board_size) & brd.board_mask; // north
    dilated |= (road_bb >> brd.board_size); // south
    dilated |= ((road_bb << 1) & ~brd.column_masks[0]) & brd.board_mask; // east
    dilated |= ((road_bb >> 1) & ~brd.column_masks[brd.board_size - 1]); // west
    return dilated & empty;
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
