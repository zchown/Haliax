
const std = @import("std");
const brd = @import("board");
const tracy = @import("tracy");
const mct = @import("monte_carlo_table");
const mvs = @import("moves");

pub const cpuct: f32 = 1.0;

// Temp Eval function type will be updated later to match the NN interface
pub const EvalFn = *const fn (
    board: *const brd.Board,
    moves: []const brd.Move,
    priors_out: []f32,
) f32;

const Trajectory = struct {
    edges: std.ArrayList(*mct.SearchEdge),

    pub fn init(allocator: std.mem.Allocator) Trajectory {
        return .{ .edges = std.ArrayList(*mct.SearchEdge).init(allocator) };
    }
    pub fn deinit(self: *Trajectory) void {
        self.edges.deinit();
    }
    pub fn reset(self: *Trajectory) void {
        self.edges.clearRetainingCapacity();
    }
};

pub const MonteCarloTreeSearch = struct {
    allocator: std.mem.Allocator,
    table: *mct.MCTable,
    eval: ?EvalFn,

    move_list: mvs.MoveList,
    prior_buf: []f32,

    pub fn init(
        allocator: std.mem.Allocator,
        table: *mct.MCTable,
        eval: ?EvalFn,
        max_moves_hint: usize,
    ) !MonteCarloTreeSearch {
        const ml = try mvs.MoveList.init(&allocator, if (max_moves_hint == 0) 256 else max_moves_hint);
        const pri = try allocator.alloc(f32, ml.capacity);
        return .{
            .allocator = allocator,
            .table = table,
            .eval = eval,
            .move_list = ml,
            .prior_buf = pri,
        };
    }

    pub fn deinit(self: *MonteCarloTreeSearch) void {
        self.allocator.free(self.prior_buf);
        self.move_list.deinit();
    }

    pub fn search(self: *MonteCarloTreeSearch, root_board: *brd.Board, num_simulations: usize) !brd.Move {
        const z = tracy.trace(@src());
        defer z.end();

        const root_node = try self.table.getOrCreateNode(root_board.zobrist_hash);

        var traj = Trajectory.init(self.allocator);
        defer traj.deinit();

        var sim: usize = 0;
        while (sim < num_simulations) : (sim += 1) {
            traj.reset();

            var node = root_node;

            while (node.expanded and node.terminal == .Unknown and node.children.items.len > 0) {
                const edge = self.selectBestEdge(node);
                try traj.edges.append(edge);

                mvs.makeMove(root_board, edge.move);
                node = try self.table.getOrCreateNode(root_board.zobrist_hash);
            }

            const leaf_value = try self.expandIfNeeded(root_board, node);

            var v: f32 = leaf_value;
            var i: usize = traj.edges.items.len;
            while (i > 0) {
                i -= 1;
                const e = traj.edges.items[i];
                e.n += 1;
                e.w += v;
                v = -v;
            }

            i = traj.edges.items.len;
            while (i > 0) {
                i -= 1;
                const e = traj.edges.items[i];
                mvs.undoMove(root_board, e.move);
            }
        }

        if (root_node.children.items.len == 0) return error.NoMoves;

        var best: *mct.SearchEdge = root_node.children.items[0];
        for (root_node.children.items[1..]) |e| {
            if (e.n > best.n) best = e;
        }
        return best.move;
    }

    fn ensurePriorCapacity(self: *MonteCarloTreeSearch, needed: usize) !void {
        if (self.prior_buf.len >= needed) return;
        var new_cap: usize = if (self.prior_buf.len == 0) 64 else self.prior_buf.len;
        while (new_cap < needed) new_cap *= 2;
        self.prior_buf = try self.allocator.realloc(self.prior_buf, new_cap);
    }

    fn totalVisits(node: *mct.SearchNode) u32 {
        var total: u32 = 0;
        for (node.children.items) |e| total += e.n;
        return total;
    }

    fn selectBestEdge(self: *MonteCarloTreeSearch, node: *mct.SearchNode) *mct.SearchEdge {
        _ = self;

        const total_n = @as(f32, @floatFromInt(totalVisits(node))) + 1.0;
        const sqrt_total = std.math.sqrt(total_n);

        var best: *mct.SearchEdge = node.children.items[0];
        var best_score: f32 = -1e30;

        for (node.children.items) |e| {
            const q = e.q();
            const n = @as(f32, @floatFromInt(e.n));
            const u = cpuct * e.prior * sqrt_total / (1.0 + n);
            const score = q + u;
            if (score > best_score) {
                best_score = score;
                best = e;
            }
        }
        return best;
    }

    fn terminalValue(board: *brd.Board) ?f32 {
        const res = board.checkResult();
        if (res.ongoing == 1) return null;

        const winner_color_int: u8 = res.color;
        if (winner_color_int == 0) return 0.0;

        const winner: brd.Color = @enumFromInt(winner_color_int);
        return if (winner == board.to_move) 1.0 else -1.0;
    }

    fn normalizePriors(priors: []f32) void {
        var sum: f32 = 0.0;
        for (priors) |p| {
            if (p > 0.0 and std.math.isFinite(p)) sum += p;
        }
        if (sum <= 0.0 or !std.math.isFinite(sum)) {
            const u: f32 = 1.0 / @as(f32, @floatFromInt(priors.len));
            for (priors) |*p| p.* = u;
            return;
        }
        const inv = 1.0 / sum;
        for (priors) |*p| {
            const v = p.*;
            p.* = if (v > 0.0 and std.math.isFinite(v)) v * inv else 0.0;
        }
    }

    fn expandIfNeeded(self: *MonteCarloTreeSearch, board: *brd.Board, node: *mct.SearchNode) !f32 {
        const z = tracy.trace(@src());
        defer z.end();

        if (terminalValue(board)) |v| {
            node.terminal = if (v > 0.0) .Win else if (v < 0.0) .Loss else .Draw;
            node.expanded = true;
            return v;
        }

        node.terminal = .Unknown;

        if (node.expanded) {
            if (self.eval) |efn| {
                self.move_list.count = 0;
                try mvs.generateMoves(board, &self.move_list);
                const moves = self.move_list.moves[0..self.move_list.count];
                if (moves.len == 0) return 0.0;

                try self.ensurePriorCapacity(moves.len);
                _ = efn(board, moves, self.prior_buf[0..moves.len]);
            }
            return 0.0;
        }

        self.move_list.count = 0;
        try mvs.generateMoves(board, &self.move_list);
        const moves = self.move_list.moves[0..self.move_list.count];

        if (moves.len == 0) {
            node.expanded = true;
            node.terminal = .Draw;
            return 0.0;
        }

        try self.ensurePriorCapacity(moves.len);

        var value: f32 = 0.0;
        if (self.eval) |efn| {
            value = efn(board, moves, self.prior_buf[0..moves.len]);
            normalizePriors(self.prior_buf[0..moves.len]);
        } else {
            const u: f32 = 1.0 / @as(f32, @floatFromInt(moves.len));
            for (self.prior_buf[0..moves.len]) |*p| p.* = u;
            value = 0.0;
        }

        try node.children.ensureTotalCapacity(moves.len);
        var i: usize = 0;
        while (i < moves.len) : (i += 1) {
            const e = try node.children.allocator.create(mct.SearchEdge);
            e.* = .{
                .move = moves[i],
                .prior = self.prior_buf[i],
                .n = 0,
                .w = 0.0,
            };
            node.children.appendAssumeCapacity(e);
        }

        node.expanded = true;
        return value;
    }
};
