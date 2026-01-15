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
    allocator: std.mem.Allocator,
    arena_alloc: std.mem.Allocator,
    board: brd.Board,
    callbaks: tei.EngineCallbacks,
    table: mcts.MCTable,
    tree_search: ts.MonteCarloTreeSearch,

    pub fn init(
        allocator: std.mem.Allocator,
        arena_allocator: std.mem.Allocator,
    ) Engine {
        return  .{
            .allocator = allocator,
            .arena_alloc = arena_allocator,
            .board = brd.Board.init(),
            .callbaks = tei.EngineCallbacks{
                .ctx = @This(),
                .onNewGame = &Engine.onNewGame,
                .onSetPosition = &Engine.onSetPosition,
                .onApplyMove = &Engine.onApplyMove,
                .onGo = &Engine.onGo,
                .onStop = &Engine.onStop,
            },
            .table = mcts.MCTable.init(arena_allocator, 1_048_576, 16 * 1024 * 1024) catch unreachable,
            .tree_search = ts.MonteCarloTreeSearch.init(
                allocator,
                @This().table,
                @This().eval,
                @This().prior,
                prior_count,
            ),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.tree_search.deinit();
        self.table.deinit();
    }

    pub fn eval(_: *brd.Board, _: []f32) f32 {
        return 0.0;
    }

    pub fn prior(_: brd.Move, _: []f32) f32 {
        return 0.0;
    }

    fn onNewGame(self: *Engine, _: usize) anyerror!void {
        self.board.reset();
    }

    fn onSetPosition(self: *Engine, tps_str: []const u8) anyerror!void {
        self.board = try tps.parseTPS(tps_str);
    }

    fn onApplyMove(self: *Engine, m: brd.Move) anyerror!void {
        try mvs.makeMove(self.board, m);
    }

    fn onGo(self: *Engine, b: *brd.Board, params: tei.GoParams) anyerror!brd.Move {
        const move = try self.tree_search.search(b, params);
        return move;
    }

    fn onStop(_: *Engine) void {
        // IGNORE
    }
};

