const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const tps = @import("tps");
const ptn = @import("ptn");
const zob = @import("zobrist");
const srch = @import("search");
const tt = @import("transposition");

const start_pos_tps = "[TPS x6/x6/x6/x6/x6/x6 1 1]";

pub const Engine = struct {
    board: brd.Board,
    allocator: *std.mem.Allocator,
    searcher: *srch.Searcher,
    tt_table: tt.TranspositionTable,
    hash_size_mb: usize = 64,
    is_searching: bool = false,

    pub fn init(allocator: *std.mem.Allocator) !Engine {
        const searcher_ptr = try allocator.create(srch.Searcher);
        errdefer allocator.destroy(searcher_ptr);

        searcher_ptr.* = srch.Searcher{};
        searcher_ptr.initInPlace();

        var engine = Engine{
            .board = brd.Board.init(),
            .allocator = allocator,
            .searcher = searcher_ptr,
            .tt_table = try tt.TranspositionTable.init(allocator, 64),
        };

        engine.searcher.tt_table = &engine.tt_table;

        // srch.quiet_lmr = srch.initQuietLMR();

        return engine;
    }

    pub fn deinit(self: *Engine) void {
        self.searcher.deinit();
        self.allocator.destroy(self.searcher);
        self.tt_table.deinit(self.allocator);
    }

    pub fn onNewGame(self: *Engine, size: usize) !void {
        _ = size;
        self.board.reset();
        self.tt_table.reset();
        self.searcher.resetHeuristics(true);
    }

    pub fn onSetPosition(self: *Engine, tps_str: []const u8) !void {
        try tps.updateBoardFromTPS(&self.board, tps_str);
    }

    pub fn onApplyMove(self: *Engine, move: brd.Move) !void {
        mvs.makeMove(&self.board, move);
    }

    pub fn onGo(self: *Engine, params: anytype) !brd.Move {
        self.is_searching = true;
        defer self.is_searching = false;

        const time_alloc = srch.calculateTimeAllocation(
            if (@hasField(@TypeOf(params), "wtime_ms")) params.wtime_ms else null,
            if (@hasField(@TypeOf(params), "btime_ms")) params.btime_ms else null,
            if (@hasField(@TypeOf(params), "winc_ms")) params.winc_ms else null,
            if (@hasField(@TypeOf(params), "binc_ms")) params.binc_ms else null,
            if (@hasField(@TypeOf(params), "movetime_ms")) params.movetime_ms else null,
            self.board.to_move,
        );

        self.searcher.max_ms = time_alloc.max_ms;
        self.searcher.ideal_ms = time_alloc.ideal_ms;
        self.searcher.stop = false;
        self.searcher.force_think = false;

        const max_depth: ?u8 = if (@hasField(@TypeOf(params), "depth"))
            if (params.depth) |d| @as(u8, @intCast(d)) else null
        else
            null;

        if (@hasField(@TypeOf(params), "nodes")) {
            self.searcher.max_nodes = params.nodes;
        }

        const result = try self.searcher.iterativeDeepening(&self.board, max_depth);
        return result.move;
    }

    pub fn onStop(self: *Engine) void {
        self.searcher.stop = true;
        tt.stop_signal.store(true, .release);
    }
};
