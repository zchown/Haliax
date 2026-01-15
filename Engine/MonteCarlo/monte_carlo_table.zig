const std = @import("std");
const zob = @import("zobrist");

pub const NodeState = enum(u8) { Unknown, Win, Loss, Draw };

pub const SearchNode = struct {
    zobrist: zob.ZobristHash,

    visits: u32 = 0,
    value: f32 = 0.0,

    parent_edge: ?*SearchEdge = null,
    parent: ?*SearchNode = null,

    children: std.ArrayList(*SearchEdge),
    expanded: bool = false,

    state: NodeState = .Unknown,
    end_in_ply: u16 = 0,
    unknown_children: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, key: zob.ZobristHash) SearchNode {
        return .{
            .zobrist = key,
            .children = std.ArrayList(*SearchEdge).init(allocator),
        };
    }

    pub fn deinit(self: *SearchNode) void {
        for (self.children.items) |e| self.children.allocator.destroy(e);
        self.children.deinit();
    }
};

pub const SearchEdge = struct {
    move: @import("board").Move,
    prior: f32,

    n: u32 = 0,
    w: f32 = 0.0,

    target: *SearchNode,

    pub inline fn q(self: *const SearchEdge) f32 {
        if (self.n == 0) return 0.0;
        return self.w / @as(f32, @floatFromInt(self.n));
    }
};

pub const TableStats = struct {
    lookups: usize = 0,
    hits: usize = 0,
    misses: usize = 0,
    inserts: usize = 0,
};

pub const MCTable = struct {
    backing_allocator: std.mem.Allocator,

    buf: []u8,
    fba: std.heap.FixedBufferAllocator,
    arena_alloc: std.mem.Allocator,

    buckets: []?*Entry,
    bucket_count: usize,

    nodes: std.ArrayList(*SearchNode),
    stats: TableStats = .{},

    const Entry = struct {
        next: ?*Entry,
        key: zob.ZobristHash,
        node: *SearchNode,
        is_used: bool = true,
    };

    pub fn init(
        backing: std.mem.Allocator,
        bucket_count_in: usize,
        arena_bytes: usize,
    ) !MCTable {
        const bucket_count = if (bucket_count_in < 1024) 1024 else bucket_count_in;

        const buf = try backing.alloc(u8, arena_bytes);
        var fba = std.heap.FixedBufferAllocator.init(buf);
        const arena_alloc = fba.allocator();

        const buckets = try backing.alloc(?*Entry, bucket_count);
        @memset(buckets, null);

        return .{
            .backing_allocator = backing,
            .buf = buf,
            .fba = fba,
            .arena_alloc = arena_alloc,
            .buckets = buckets,
            .bucket_count = bucket_count,
            .nodes = std.ArrayList(*SearchNode).init(backing),
            .stats = .{},
        };
    }

    pub fn deinit(self: *MCTable) void {
        self.backing_allocator.free(self.buckets);

        self.nodes.deinit();

        self.backing_allocator.free(self.buf);
    }

    fn bucketIndex(self: *const MCTable, key: zob.ZobristHash) usize {
        return @as(usize, @intCast(key)) % self.bucket_count;
    }

    pub fn get(self: *MCTable, key: zob.ZobristHash) ?*SearchNode {
        self.stats.lookups += 1;

        const idx = self.bucketIndex(key);
        var e = self.buckets[idx];
        while (e) |cur| : (e = cur.next) {
            if (cur.key == key and cur.is_used) {
                self.stats.hits += 1;
                return cur.node;
            }
        }
        self.stats.misses += 1;
        return null;
    }

    pub fn getOrCreateNode(self: *MCTable, key: zob.ZobristHash) !*SearchNode {
        if (self.get(key)) |n| return n;

        const node = try self.arena_alloc.create(SearchNode);
        node.* = SearchNode.init(self.arena_alloc, key);

        try self.nodes.append(node);

        const idx = self.bucketIndex(key);
        const ent = try self.arena_alloc.create(Entry);
        ent.* = .{
            .next = self.buckets[idx],
            .key = key,
            .node = node,
            .is_used = true,
        };
        self.buckets[idx] = ent;

        self.stats.inserts += 1;
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

    pub fn shouldResetArena(self: *const MCTable) bool {
        const used = self.fba.end_index;
        return used * 2 >= self.buf.len;
    }

    pub fn clear(self: *MCTable) void {
        @memset(self.buckets, null);
        self.nodes.clearRetainingCapacity();

        self.fba.reset();
        self.arena_alloc = self.fba.allocator();

        self.stats = .{};
    }
};
