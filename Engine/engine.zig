const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const tps = @import("tps");
const ptn = @import("ptn");
const tei = @import("tei");
const ts = @import("tree_search");
const mcts = @import("monte_carlo_table");
const tracy = @import("tracy");

const prior_count = 16;

pub const Engine = struct {
    allocator: *std.mem.Allocator,
    board: brd.Board,
    tree_search: ts.MonteCarloTreeSearch,

    pub fn init(
        allocator: *std.mem.Allocator,
    ) !Engine {
        var e = Engine{
            .allocator = allocator,
            .board = brd.Board.init(),
            .tree_search = undefined,
        };
        e.tree_search = try ts.MonteCarloTreeSearch.init(allocator, eval, false, true);
        return e;
    }

    pub fn deinit(self: *Engine) void {
        self.tree_search.deinit();
    }

    pub fn eval(b: *const brd.Board, _: []f32) f32 {
        if (b.to_move == brd.Color.White) {
            return b.white_vector.data[25 * 36 + 5];
        } else {
            return b.black_vector.data[25 * 36 + 5];
        }
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
            .max_simulations = 5000,
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

