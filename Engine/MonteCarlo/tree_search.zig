const std = @import("std");
const brd = @import("board");
const zob = @import("zobrist");
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

pub const SearchNode = struct {
    hash: zob.ZobristHash,
};

pub const SearchEdge = struct {
    move: brd.Move,
};

pub const SearchParams = struct {
    max_simulations: usize,
    max_time_ms: usize,
};

pub const MonteCarloTreeSearch = struct {
    allocator: *std.mem.Allocator,
    move_list: mvs.MoveList,

    pub fn init(alloc: *std.mem.Allocator) !MonteCarloTreeSearch {
        return MonteCarloTreeSearch{
            .allocator = alloc,
            .move_list = try mvs.MoveList.init(alloc, 512),
        };
    }

    pub fn deinit(_: *MonteCarloTreeSearch) void {
    }

    pub fn search(self: *MonteCarloTreeSearch, board: *brd.Board, _: SearchParams) !brd.Move {
        tracy.frameMarkNamed("MCTS Search");
        const tr = tracy.trace(@src());
        defer tr.end();

        self.move_list.clear();
        try mvs.generateMoves(board, &self.move_list);
        if (self.move_list.count == 0) {
            return error.NoLegalMoves;
        }
        return self.move_list.moves[0];
    }
};
