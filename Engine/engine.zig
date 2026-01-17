const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const tps = @import("tps");
const ptn = @import("ptn");
const tei = @import("tei");
const ts = @import("tree_search");
const nn = @import("nn_eval");
const tracy = @import("tracy");

const prior_count = 16;

pub const Engine = struct {
    allocator: *std.mem.Allocator,
    board: brd.Board,
    tree_search: ts.MonteCarloTreeSearch,
    nn_eval: nn.NNEval,

    pub fn init(
        allocator: *std.mem.Allocator,
        model_path: []const u8,
    ) !Engine {
        var e = Engine{
            .allocator = allocator,
            .board = brd.Board.init(),
            .tree_search = undefined,
            .nn_eval = undefined,
        };

        e.nn_eval = try nn.NNEval.init(allocator.*, model_path);

        e.tree_search = try ts.MonteCarloTreeSearch.init(allocator, &e.nn_eval, evalThunk, false, false);
        return e;
    }

    pub fn deinit(self: *Engine) void {
        self.tree_search.deinit();
        self.nn_eval.deinit();
    }

    fn evalThunk(ctx: *anyopaque, b: *const brd.Board, moves: []const brd.Move, priors_out: []f32) f32 {
        const nne: *nn.NNEval = @ptrCast(@alignCast(ctx));
        return nne.eval(b, moves, priors_out);
    }

    pub fn onNewGame(self: *Engine, _: usize) anyerror!void {
        self.board.reset();
    }

    pub fn onSetPosition(self: *Engine, tps_str: []const u8) anyerror!void {
        try tps.updateBoardFromTPS(&self.board, tps_str);
    }

    pub fn onApplyMove(self: *Engine, m: brd.Move) anyerror!void {
        mvs.makeMove(&self.board, m);
    }

    pub fn onGo(self: *Engine, _: tei.GoParams) anyerror!brd.Move {
        const params = ts.SearchParams{
            .max_simulations = 1000,
            .max_time_ms = 0,
        };
        const move = try self.tree_search.search(&self.board, params);
        mvs.makeMove(&self.board, move);
        return move;
    }

    pub fn onStop(_: *Engine) void {
        // IGNORE
    }
};

