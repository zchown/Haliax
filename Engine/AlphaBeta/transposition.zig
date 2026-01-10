const std = @import("std");
const zob = @import("zobrist");
const brd = @import("board");

pub const EstimationType = enum {
    Under,
    Over,
    Exact,
};

const do_stat_tracking = true;

const TranspositionTable = @This();

entries: []TableEntry,
stats: TableStats,

const TableEntry = struct {
    move: brd.Move,
    score: isize,
    depth: usize,
    estimation: EstimationType,
    hash: zob.ZobristHash,
};

const TableStats = struct {
    hits: usize = 0,
    misses: usize = 0,
    depth_rewrites: usize = 0,
    updates: usize = 0,
    lookups: usize = 0,
    fill: f64 = 0,

    pub inline fn incrementLookup(self: *TableStats) void {
        if(!do_stat_tracking) return;

        self.lookups++;
    }
};

pub fn init(allocator: std.mem.Allocator, capacity: usize) !TranspositionTable {
    const e = try allocator.alloc(TableEntry, capacity);
    return TranspositionTable{
        .entries = e,
        .stats = TableStats{},
    };
}

pub fn deinit(self: *TranspositionTable, allocator: std.mem.Allocator) void {
    allocator.free(self.entries);
    allocator.free(self);
}

