const std = @import("std");
const brd = @import("board");
const zob = @import("zobrist");
const tracy = @import("tracy");
const mvs = @import("moves");
const ptn = @import("ptn");
const tps = @import("tps");

pub const cpuct: f32 = 1.0;

pub const EvalFn = *const fn (
    ctx: *anyopaque,
    board: *const brd.Board,
    moves: []const brd.Move,
    priors_out: []f32,
) f32;

pub const SearchParams = struct {
    max_simulations: usize = 5000,
    max_time_ms: usize = 0, // 0 means "no time limit"
};

pub const RootStats = struct {
    moves: []const brd.Move,
    visit_counts: []u32,
};

const Node = struct {
    hash: zob.ZobristHash,

    visits: u32 = 0,
    value_sum: f32 = 0.0,

    expanded: bool = false,

    moves: []brd.Move = &[_]brd.Move{},
    priors: []f32 = &[_]f32{},
    child_visits: []u32 = &[_]u32{},
    child_value_sum: []f32 = &[_]f32{},
    child_ptrs: []*Node = &[_]*Node{},

    inline fn qValue(self: *const Node) f32 {
        if (self.visits == 0) return 0.0;
        return self.value_sum / @as(f32, @floatFromInt(self.visits));
    }

    inline fn childQ(self: *const Node, i: usize) f32 {
        const v = self.child_visits[i];
        if (v == 0) return 0.0;
        return self.child_value_sum[i] / @as(f32, @floatFromInt(v));
    }
};

pub const MonteCarloTreeSearch = struct {
    allocator: *std.mem.Allocator,
    eval_ctx: *anyopaque,
    eval_fn: EvalFn,

    move_list: mvs.MoveList,
    made_move_list: mvs.MoveList,

    arena: std.heap.ArenaAllocator,
    node_map: std.AutoHashMap(zob.ZobristHash, *Node),

    debug_mode: bool,
    training_mode: bool,

    last_root: ?*RootStats,

    pub fn init(alloc: *std.mem.Allocator, eval_ctx: *anyopaque, eval_fn: EvalFn, dm: bool, tm: bool) !MonteCarloTreeSearch {
        var arena = std.heap.ArenaAllocator.init(alloc.*);
        errdefer arena.deinit();

        return MonteCarloTreeSearch{
            .allocator = alloc,
            .eval_ctx = eval_ctx,
            .eval_fn = eval_fn,
            .move_list = try mvs.MoveList.init(alloc, 512),
            .made_move_list = try mvs.MoveList.init(alloc, 512),
            .arena = arena,
            .node_map = std.AutoHashMap(zob.ZobristHash, *Node).init(arena.allocator()),
            .debug_mode = dm,
            .training_mode = tm,
            .last_root = null,
        };
    }

    pub fn deinit(self: *MonteCarloTreeSearch) void {
        self.move_list.deinit();
        self.node_map.deinit();
        self.arena.deinit();
    }

    pub fn getLastRootStats(self: *MonteCarloTreeSearch) ?RootStats {
        if (self.last_root) |lr| {
            return RootStats{
                .moves = lr.moves,
                .visit_counts = lr.visit_counts,
            };
        }
        return null;
    }

    fn resetSearchState(self: *MonteCarloTreeSearch) void {
        // Keep capacity to avoid churn between searches.
        _ = self.arena.reset(.retain_capacity);
        self.node_map = std.AutoHashMap(zob.ZobristHash, *Node).init(self.arena.allocator());
    }

    fn terminalValue(board: *brd.Board) ?f32 {
        const r = board.checkResult();
        if (r.ongoing == 1) return null;

        // Draw
        if (@as(u4, @bitCast(r)) == 0) return 0.0;

        const winner: brd.Color = if (r.color == 0) .White else .Black;
        // Value is from perspective of side to move at this node.
        return if (winner == board.to_move) 1.0 else -1.0;
    }

    fn getOrCreateNode(self: *MonteCarloTreeSearch, hash: zob.ZobristHash) !*Node {
        if (self.node_map.get(hash)) |n| return n;

        const n = try self.arena.allocator().create(Node);
        n.* = Node{ .hash = hash };
        try self.node_map.put(hash, n);
        return n;
    }

    fn expand(self: *MonteCarloTreeSearch, node: *Node, board: *brd.Board) !f32 {
        self.move_list.clear();
        try mvs.generateMoves(board, &self.move_list);

        // Shouldn't ever happen
        if (self.move_list.count == 0) {
            node.expanded = true;
            node.moves = &[_]brd.Move{};
            node.priors = &[_]f32{};
            node.child_visits = &[_]u32{};
            node.child_value_sum = &[_]f32{};
            node.child_ptrs = &[_]*Node{};
            return 0.0;
        }

        const count = self.move_list.count;

        node.moves = try self.arena.allocator().alloc(brd.Move, count);
        node.priors = try self.arena.allocator().alloc(f32, count);
        node.child_visits = try self.arena.allocator().alloc(u32, count);
        node.child_value_sum = try self.arena.allocator().alloc(f32, count);
        node.child_ptrs = try self.arena.allocator().alloc(*Node, count);

        std.mem.copyForwards(brd.Move, node.moves, self.move_list.moves[0..count]);

        @memset(node.child_visits, 0);
        @memset(node.child_value_sum, 0.0);

        const value = self.eval_fn(self.eval_ctx, board, node.moves, node.priors);

        // Keep priors sane (non-negative + normalized), but do NOT overwrite with uniform.
        var sum: f32 = 0.0;
        for (node.priors) |*p| {
            if (p.* < 0) p.* = 0;
            sum += p.*;
        }
        if (sum <= 0.0) {
            const u = 1.0 / @as(f32, @floatFromInt(count));
            for (node.priors) |*p| p.* = u;
        } else {
            const inv = 1.0 / sum;
            for (node.priors) |*p| p.* *= inv;
        }

        for (node.child_ptrs) |*c| c.* = undefined;

        node.expanded = true;
        return value;
    }

    fn selectChild(self: *MonteCarloTreeSearch, node: *Node) usize {
        // PUCT: argmax_i (Q_i + U_i)
        const parent_visits_f = @as(f32, @floatFromInt(@max(node.visits, 1)));
        const sqrt_parent = std.math.sqrt(parent_visits_f);

        var best_i: usize = 0;
        var best_score: f32 = -std.math.inf(f32);

        for (node.moves, 0..) |_, i| {
            const q = node.childQ(i);
            const n_i = @as(f32, @floatFromInt(node.child_visits[i]));
            const u = cpuct * node.priors[i] * (sqrt_parent / (1.0 + n_i));
            const score = q + u;
            if (score > best_score) {
                best_score = score;
                best_i = i;
            }
        }
        _ = self; // suppress unused warning
        return best_i;
    }

    fn simulate(self: *MonteCarloTreeSearch, board: *brd.Board, root: *Node) !void {
        // Store traversed (node, child_index) for backprop.
        var path_nodes: [256]*Node = undefined;
        var path_edges: [256]usize = undefined;
        var depth: usize = 0;

        var node = root;

        while (true) {
            if (terminalValue(board)) |tv| {
                var value = tv;

                node.visits += 1;
                node.value_sum += value;

                while (depth > 0) {
                    depth -= 1;
                    value = -value;

                    const parent = path_nodes[depth];
                    const ei = path_edges[depth];

                    parent.visits += 1;
                    parent.value_sum += value;
                    parent.child_visits[ei] += 1;
                    parent.child_value_sum[ei] += value;
                }
                return;
            }

            if (!node.expanded) {
                const v = try self.expand(node, board);

                var value = v;

                node.visits += 1;
                node.value_sum += value;

                while (depth > 0) {
                    depth -= 1;
                    value = -value;

                    const parent = path_nodes[depth];
                    const ei = path_edges[depth];

                    parent.visits += 1;
                    parent.value_sum += value;
                    parent.child_visits[ei] += 1;
                    parent.child_value_sum[ei] += value;
                }
                return;
            }

            // Pick best child by PUCT.
            const ei = self.selectChild(node);
            const mv = node.moves[ei];

            if (depth >= path_nodes.len) {
                // Depth cap fallback: treat as draw-ish.
                var value: f32 = 0.0;

                node.visits += 1;
                node.value_sum += value;

                while (depth > 0) {
                    depth -= 1;
                    value = -value;

                    const parent = path_nodes[depth];
                    const pei = path_edges[depth];

                    parent.visits += 1;
                    parent.value_sum += value;
                    parent.child_visits[pei] += 1;
                    parent.child_value_sum[pei] += value;
                }
                return;
            }

            path_nodes[depth] = node;
            path_edges[depth] = ei;
            depth += 1;

            self.move_list.clear();
            try mvs.generateMoves(board, &self.move_list);

            mvs.makeMove(board, mv);
            try self.made_move_list.append(mv);

            const child_hash = board.zobrist_hash;
            const child = try self.getOrCreateNode(child_hash);
            node.child_ptrs[ei] = child;
            node = child;
        }
    }

    fn pickBestMove(root: *Node) brd.Move {
        // Choose move with highest visit count (ties by prior).
        var best_i: usize = 0;
        var best_visits: u32 = 0;
        var best_prior: f32 = -1.0;

        for (root.moves, 0..) |_, i| {
            const v = root.child_visits[i];
            if (v > best_visits or (v == best_visits and root.priors[i] > best_prior)) {
                best_i = i;
                best_visits = v;
                best_prior = root.priors[i];
            }
        }
        return root.moves[best_i];
    }

    fn pickBestMoveDebug(root: *Node, seed: u64) brd.Move {
        // choose move with probability proportional to visit count
        var total_visits: u32 = 0;
        for (root.child_visits) |v| {
            total_visits += v;
        }
        var s = seed;
        var r = zob.splitMix64(&s) % @as(u64, total_visits);
        for (root.moves, 0..) |_, i| {
            const v = root.child_visits[i];
            if (@as(u64, v) > r) {
                return root.moves[i];
            }
            r -= @as(u64, v);
        }
        return root.moves[0];
    }

    pub fn search(self: *MonteCarloTreeSearch, board: *brd.Board, params: SearchParams) !brd.Move {
        tracy.frameMarkNamed("MCTS Search");
        const tr = tracy.trace(@src());
        defer tr.end();

        self.resetSearchState();

        const root = try self.getOrCreateNode(board.zobrist_hash);

        if (!root.expanded) _ = try self.expand(root, board);

        const start_ms: i64 = std.time.milliTimestamp();
        var sims: usize = 0;

        while (sims < params.max_simulations) : (sims += 1) {
            self.made_move_list.clear();
            if (params.max_time_ms != 0) {
                const now = std.time.milliTimestamp();
                if (@as(usize, @intCast(now - start_ms)) >= params.max_time_ms) break;
            }

            try self.simulate(board, root);

            while (self.made_move_list.count > 0) {
                const mv = self.made_move_list.pop();
                mvs.undoMove(board, mv);
            }
        }

        var m: brd.Move = undefined;
        if (self.training_mode) {
            const seed = std.time.milliTimestamp();
            m = pickBestMoveDebug(root, @as(u64, @intCast(seed)));
        } else {
            m = pickBestMove(root);
        }

        const end_ms: i64 = std.time.milliTimestamp();

        if (self.debug_mode) {
            std.debug.print("MCTS Search completed {d} simulations.\n", .{sims});
            for (root.moves, 0..) |mv, i| {
                const v = root.child_visits[i];
                const q = root.childQ(i);
                const p = root.priors[i];
                std.debug.print(
                    "Move: {s}, Visits: {}, Q: {}, P: {}\n",
                    .{ try ptn.moveToString(self.allocator, mv), v, q, p },
                );
            }

            std.debug.print("Selected move: {s}\n", .{try ptn.moveToString(self.allocator, m)});
            std.debug.print("Time taken: {d} ms\n", .{@as(usize, @intCast(end_ms - start_ms))});
        }

        return m;
    }
};

