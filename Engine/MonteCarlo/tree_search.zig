const std = @import("std");
const brd = @import("board");
const tracy = @import("tracy");
const mct = @import("monte_carlo_table");
const mvs = @import("moves");
const tei = @import("tei");

pub const cpuct: f32 = 1.0;

pub const EvalFn = *const fn (
board: *const brd.Board,
priors_out: []f32,
) f32;

pub const PriorFn = *const fn (
    move: brd.Move,
    priors_out: []f32,
) f32;

const NodeState = mct.NodeState;

const Trajectory = struct {
    nodes: std.ArrayList(*mct.SearchNode),
    edges: std.ArrayList(*mct.SearchEdge),

    pub fn init(allocator: std.mem.Allocator) Trajectory {
        return .{
            .nodes = std.ArrayList(*mct.SearchNode).init(allocator),
            .edges = std.ArrayList(*mct.SearchEdge).init(allocator),
        };
    }

    pub fn deinit(self: *Trajectory) void {
        self.nodes.deinit();
        self.edges.deinit();
    }

    pub fn reset(self: *Trajectory) void {
        self.nodes.clearRetainingCapacity();
        self.edges.clearRetainingCapacity();
    }

    pub fn push(self: *Trajectory, node: *mct.SearchNode, edge: *mct.SearchEdge) !void {
        try self.nodes.append(node);
        try self.edges.append(edge);
    }

    pub fn len(self: *const Trajectory) usize {
        std.debug.assert(self.nodes.items.len == self.edges.items.len);
        return self.edges.items.len;
    }
};

pub const MonteCarloTreeSearch = struct {
    allocator: std.mem.Allocator,
    table: *mct.MCTable,
    eval_fn: EvalFn,
    prior_fn: PriorFn,

    move_list: mvs.MoveList,
    prior_buf: []f32,

    pub fn init(
    allocator: std.mem.Allocator,
    table: *mct.MCTable,
    eval_fn: EvalFn,
    prior_fn: PriorFn,
    max_priors: usize,
) !MonteCarloTreeSearch {
        return .{
            .allocator = allocator,
            .table = table,
            .eval_fn = eval_fn,
            .prior_fn = prior_fn,
            .move_list = try mvs.MoveList.init(&allocator, 2048),
            .prior_buf = try allocator.alloc(f32, max_priors),
        };
    }

    pub fn deinit(self: *MonteCarloTreeSearch) void {
        self.move_list.deinit();
        self.allocator.free(self.prior_buf);
    }

    pub fn search(
    self: *MonteCarloTreeSearch,
    board: *brd.Board,
    params: tei.GoParams,
) !brd.Move {
        const frame = tracy.frameMarkNamed("MCTS Search");
        _ = frame;

        if (self.table.shouldResetArena()) {
            self.table.clear();
        }

        const root = try self.table.getOrCreateNode(board.zobrist_hash);
        self.table.markAsUsed(root.zobrist);

        const iterations: u32 = if (params.nodes) |n|
            @as(u32, @intCast(@min(n, @as(u64, std.math.maxInt(u32)))))
            else if (params.depth) |d|
                @as(u32, 1) << @as(u5, @intCast(@min(d, 16)))
                else
                1 << 12;

        var traj = Trajectory.init(self.allocator);
        defer traj.deinit();

        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            traj.reset();

            const leaf_value = try self.selectExpand(board, root, &traj);

            self.backPropagate(root, leaf_value, &traj);
        }

        var best: ?*mct.SearchEdge = null;
        var best_n: u32 = 0;

        for (root.children.items) |e| {
            if (e.target.state == .Loss) return e.move;
        }

        for (root.children.items) |e| {
            if (e.n > best_n) {
                best_n = e.n;
                best = e;
            }
        }

        if (best) |b| return b.move;

        std.debug.assert(false, "MCTS search found no best move");

        // Fallback: generate and return first legal move
        self.move_list.clear();
        try mvs.generateMoves(board, &self.move_list);
        if (self.move_list.count == 0) return brd.Move{ .position = 0, .pattern = 0, .flag = 0 };
        return self.move_list.moves[0];
    }

    fn terminalValue(board: *brd.Board) ?f32 {
        const r = board.checkResult();
        if (r.ongoing == 1) return null;

        if (r.road == 0 and r.flat == 0) return 0.0;

        const winner: brd.Color = if (r.color == 0) .White else .Black;

        if (winner == board.to_move) return 1.0 else return -1.0;
    }

    fn setNodeTerminalFromBoard(node: *mct.SearchNode, board: *brd.Board) void {
        const r = board.checkResult();
        if (r.ongoing == 1) return;

        if (r.road == 0 and r.flat == 0) {
            node.state = .Draw;
            node.end_in_ply = 0;
            return;
        }

        const winner: brd.Color = if (r.color == 0) .White else .Black;

        node.state = if (winner == board.to_move) .Win else .Loss;
        node.end_in_ply = 0;
    }

    fn selectExpand(
    self: *MonteCarloTreeSearch,
    board: *brd.Board,
    root: *mct.SearchNode,
    traj: *Trajectory,
) !f32 {
        var node = root;

        while (node.expanded and node.state == .Unknown) {
            const edge = self.selectBestEdgePUCT(node) orelse break;

            try traj.edges.append(edge);

            mvs.makeMove(board, edge.move);

            if (terminalValue(board)) |tv| {
                setNodeTerminalFromBoard(edge.target, board);
                mvs.undoMove(board, edge.move);

                for (traj.edges.items) |e2| {
                    _ = e2;
                }
                return tv;
            }

            node = edge.target;
            try traj.nodes.append(node);
        }

        if (node.state != .Unknown) {
            const v: f32 = switch (node.state) {
                .Win => 1.0,
                .Loss => -1.0,
                .Draw => 0.0,
                .Unknown => unreachable,
            };

            // Undo trajectory moves
            var j: isize = @as(isize, @intCast(traj.edges.items.len)) - 1;
            while (j >= 0) : (j -= 1) {
                mvs.undoMove(board, traj.edges.items[@as(usize, @intCast(j))].move);
            }
            return v;
        }

        if (terminalValue(board)) |tv| {
            setNodeTerminalFromBoard(node, board);

            var j: isize = @as(isize, @intCast(traj.edges.items.len)) - 1;
            while (j >= 0) : (j -= 1) {
                mvs.undoMove(board, traj.edges.items[@as(usize, @intCast(j))].move);
            }
            return tv;
        }

        self.move_list.clear();
        try mvs.generateMoves(board, &self.move_list);
        const moves = self.move_list.moves[0..self.move_list.count];

        if (moves.len == 0) {
            // No moves: something has gone wrong, treat as draw
            var j: isize = @as(isize, @intCast(traj.edges.items.len)) - 1;
            while (j >= 0) : (j -= 1) {
                mvs.undoMove(board, traj.edges.items[@as(usize, @intCast(j))].move);
            }
            std.debug.assert(false, "MCTS selectExpand found no legal moves in non-terminal position");
            return 0.0;
        }

        const leaf_value = self.eval_fn(board, self.prior_buf);

        node.expanded = true;
        node.children.clearRetainingCapacity();
        try node.children.ensureTotalCapacity(moves.len);

        node.unknown_children = 0;

        for (0..moves.len) |i| {
            const mv = moves[i];
            mvs.makeMove(board, mv);
            const child = try self.table.getOrCreateNode(board.zobrist_hash);
            self.table.markAsUsed(child.zobrist);

            self.setNodeTerminalFromBoard(child, board);
            if (child.state == .Unknown) node.unknown_children += 1;

            mvs.undoMove(board, mv);

            const e = try self.table.arena_alloc.create(mct.SearchEdge);
            e.* = .{
                .move = mv,
                .prior = self.prior_fn(mv, self.prior_buf),
                .n = 0,
                .w = 0.0,
                .target = child,
            };

            node.children.appendAssumeCapacity(e);
        }

        // Undo trajectory moves
        var j: isize = @as(isize, @intCast(traj.edges.items.len)) - 1;
        while (j >= 0) : (j -= 1) {
            mvs.undoMove(board, traj.edges.items[@as(usize, @intCast(j))].move);
        }

        return leaf_value;
    }

    fn selectBestEdgePUCT(self: *MonteCarloTreeSearch, node: *mct.SearchNode) ?*mct.SearchEdge {
        _ = self;

        if (node.children.items.len == 0) return null;

        // If any move makes opponent proven losing, choose it immediately.
        for (node.children.items) |e| {
            if (e.target.state == .Loss) return e;
        }

        const parent_n: f32 = @as(f32, @floatFromInt(@max(node.visits, 1)));
        const sqrt_parent = std.math.sqrt(parent_n);

        var best: ?*mct.SearchEdge = null;
        var best_score: f32 = -1e30;

        // Skip immediate losing moves if there exist alternatives
        var all_losing = true;
        for (node.children.items) |e| {
            if (e.target.state != .Win) { // not losing for us
                all_losing = false;
                break;
            }
        }

        for (node.children.items) |e| {
            if (!all_losing and e.target.state == .Win) continue;

            const q = e.q();
            const u = cpuct * e.prior * sqrt_parent / (1.0 + @as(f32, @floatFromInt(e.n)));

            // small progressive bias
            const pb: f32 = 0.05 / (1.0 + @as(f32, @floatFromInt(e.n)));

            const score = q + u + pb;
            if (score > best_score) {
                best_score = score;
                best = e;
            }
        }

        return best;
    }

    fn backPropagate(
    self: *MonteCarloTreeSearch,
    root: *mct.SearchNode,
    leaf_value_in: f32,
    traj: *Trajectory,
) void {
        _ = self;

        root.visits += 1;
        root.value += (leaf_value_in - root.value) / @as(f32, @floatFromInt(root.visits));

        var value: f32 = leaf_value_in;

        var i: isize = @as(isize, @intCast(traj.len())) - 1;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @as(usize, @intCast(i));

            const node = traj.nodes.items[idx]; // parent node at this ply
            const edge = traj.edges.items[idx]; // edge chosen from parent node

            value = -value;

            edge.n += 1;
            edge.w += value;

            node.visits += 1;
            node.value += (value - node.value) / @as(f32, @floatFromInt(node.visits));

            if (node.expanded and node.state == .Unknown and node.children.items.len != 0) {
                var unknown: u32 = 0;
                var saw_draw = false;

                var best_win: u16 = std.math.maxInt(u16); // win in min ply
                var worst: u16 = 0;                      // loss/draw in max ply

                for (node.children.items) |e| {
                    const c = e.target;
                    if (c.state == .Unknown) {
                        unknown += 1;
                        continue;
                    }

                    const d: u16 = c.end_in_ply + 1;

                    if (c.state == .Loss) {
                        if (d < best_win) best_win = d;
                    } else if (c.state == .Draw) {
                        saw_draw = true;
                        if (d > worst) worst = d;
                    } else {
                        if (d > worst) worst = d;
                    }
                }

                node.unknown_children = unknown;

                if (unknown == 0) {
                    if (best_win != std.math.maxInt(u16)) {
                        node.state = .Win;
                        node.end_in_ply = best_win;
                    } else if (saw_draw) {
                        node.state = .Draw;
                        node.end_in_ply = worst;
                    } else {
                        node.state = .Loss;
                        node.end_in_ply = worst;
                    }
                }
            }
        }
    }

};

