const std = @import("std");
const brd = @import("board");
const zob = @import("zobrist");
const tracy = @import("tracy");

pub const NodeState = enum(u8) { Unknown, Win, Loss, Draw };

pub const SearchEdge = struct {
    move: brd.Move,
    prior: f32,
    n: u32 = 0,
    w: f32 = 0.0,

    pub inline fn q(self: *const SearchEdge) f32 {
        if (self.n == 0) return 0.0;
        return self.w / @as(f32, @floatFromInt(self.n));
    }
};

pub const SearchNode = struct {
    zobrist: zob.ZobristHash,
    children: std.ArrayList(*SearchEdge),
    terminal: NodeState = .Unknown,
    expanded: bool = false,

    pub fn init(allocator: std.mem.Allocator, key: zob.ZobristHash) SearchNode {
        return .{
            .zobrist = key,
            .children = std.ArrayList(*SearchEdge).init(allocator),
            .terminal = .Unknown,
            .expanded = false,
        };
    }

    pub fn deinit(self: *SearchNode) void {
        for (self.children.items) |edge| self.children.allocator.destroy(edge);
        self.children.deinit();
    }
};



pub const TableStats = struct {
    lookups: usize = 0,
    hits: usize = 0,
    misses: usize = 0,
    inserts: usize = 0,
};

pub const MCTable = struct {
    allocator: std.mem.Allocator,
    buckets: []?*Entry,
    stats: TableStats = .{},

    nodes: std.ArrayList(*SearchNode),

    const Entry = struct {
        next: ?*Entry,
        key: zob.ZobristHash,
        node: *SearchNode,
        is_used: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, bucket_count: usize) !MCTable {
        const n = if (bucket_count < 1024) 1024 else bucket_count;
        const buckets = try allocator.alloc(?*Entry, n);
        @memset(buckets, null);

        return .{
            .allocator = allocator,
            .buckets = buckets,
            .stats = .{},
            .nodes = std.ArrayList(*SearchNode).init(allocator),
        };
    }

    pub fn deinit(self: *MCTable) void {
        for (self.buckets) |head| {
            var e = head;
            while (e) |cur| {
                e = cur.next;
                self.allocator.destroy(cur);
            }
        }
        self.allocator.free(self.buckets);

        for (self.nodes.items) |n| {
            n.deinit();
            self.allocator.destroy(n);
        }
        self.nodes.deinit();
    }

    fn bucketIndex(self: *const MCTable, key: zob.ZobristHash) usize {
        return @as(usize, @intCast(key)) % self.buckelen;
    }

    pub fn get(self: *MCTable, key: zob.ZobristHash) ?*SearchNode {
        self.stalookups += 1;

        const idx = self.bucketIndex(key);
        var e = self.buckets[idx];
        while (e) |cur| : (e = cur.next) {
            if (cur.key == key and cur.is_used) {
                self.stahits += 1;
                return cur.node;
            }
        }
        self.stamisses += 1;
        return null;
    }

    pub fn getOrCreateNode(self: *MCTable, key: zob.ZobristHash) !*SearchNode {
        if (self.get(key)) |n| return n;

        const node = try self.allocator.create(SearchNode);
        node.* = SearchNode.init(self.allocator, key);
        try self.nodes.append(node);

        const idx = self.bucketIndex(key);
        const ent = try self.allocator.create(Entry);
        ent.* = .{
            .next = self.buckets[idx],
            .key = key,
            .node = node,
            .is_used = true,
        };
        self.buckets[idx] = ent;

        self.stainserts += 1;
        return node;
    }

    pub fn markAsUnused(self: *MCTable, key: zob.ZobristHash) void {
        const idx = self.bucketIndex(key);
        var e = self.buckets[idx];
        while (e) |cur| : (e = cur.next) {
            if (cur.key == key and cur.is_used) cur.is_used = false;
        }
    }

    pub fn markAsUsed(self: *MCTable, key: zob.ZobristHash) void {
        const idx = self.bucketIndex(key);
        var e = self.buckets[idx];
        while (e) |cur| : (e = cur.next) {
            if (cur.key == key) cur.is_used = true;
        }
    }
};
