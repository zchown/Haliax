const std = @import("std");
const brd = @import("board");
const zobrist = @import("zobrist");
const tracy = @import("tracy");
const tracy_enable = tracy.build_options.enable_tracy;

// not doing path compression can be faster
const do_compression = true;

const EdgeMask = packed struct(u4) {
    north: u1 = 0,
    south: u1 = 0,
    east: u1 = 0,
    west: u1 = 0,
};

// disjoint set forest for road detection
pub const RoadUF = struct {
    parent: [brd.num_squares]usize,
    rank: [brd.num_squares]usize,
    active: [brd.num_squares]bool,
    edges: [brd.num_squares]EdgeMask,
    has_road_h: bool,
    has_road_v: bool,

    pub fn init() RoadUF {
        var uf = RoadUF{
            .parent = [_]usize{0} ** brd.num_squares,
            .rank = [_]usize{0} ** brd.num_squares,
            .active = [_]bool{false} ** brd.num_squares,
            .edges = [_]EdgeMask{EdgeMask{}} ** brd.num_squares,
            .has_road_h = false,
            .has_road_v = false,
        };
        uf.clear();
        return uf;
    }

    pub fn clear(self: *RoadUF) void {
        @memset(&self.rank, 0);
        @memset(&self.active, false);
        @memset(&self.edges, EdgeMask{});
        self.has_road_h = false;
        self.has_road_v = false;

        for (0..brd.num_squares) |i| {
            self.parent[i] = i;
        }
    }

    fn edgeMaskForPos(pos: brd.Position) EdgeMask {
        const row: usize = @divFloor(@as(usize, @intCast(pos)), brd.board_size);
        const col: usize = @as(usize, @intCast(pos)) % brd.board_size;

        var mask: EdgeMask = EdgeMask{};
        mask.north = @intFromBool(row == brd.board_size - 1);
        mask.south = @intFromBool(row == 0);
        mask.west = @intFromBool(col == 0);
        mask.east = @intFromBool(col == brd.board_size - 1);

        // std.debug.print("Pos: {},{} Mask N:{} S:{} E:{} W:{}\n", .{row, col, mask.north, mask.south, mask.east, mask.west});
        return mask;
    }

    fn find(self: *RoadUF, i: usize) usize {
        if (tracy_enable) {
            const z = tracy.trace(@src());
            defer z.end();
        }
        var x = i;

        // find
        while (x != self.parent[x]) : (x = self.parent[x]) {}

        const root = x;

        x = i;
        // compress
        if (do_compression) {
            while (self.parent[x] != root) {
                const next = self.parent[x];
                self.parent[x] = root;
                x = next;
            }
        }
        else {
            // single hop
            self.parent[i] = root;
        }
        return root;
    }

    fn unionUF(self: *RoadUF, a: usize, b: usize) void {
        if (tracy_enable) {
            const z = tracy.trace(@src());
            defer z.end();
        }
        const ra = self.find(a);
        const rb = self.find(b);
        if (ra == rb) return;

        var r1 = ra;
        var r2 = rb;
        if (self.rank[r1] < self.rank[r2]) {
            r1 = rb;
            r2 = ra;
        }

        self.parent[r2] = r1;
        if (self.rank[r1] == self.rank[r2]) {
            self.rank[r1] += 1;
        }

        const combined_edges_int: u4 = @as(u4, @bitCast(self.edges[r1])) | @as(u4, @bitCast(self.edges[r2]));
        self.edges[r1] = @bitCast(combined_edges_int);

        self.has_road_h = self.has_road_h or ((combined_edges_int & 0b1100) == 0b1100);
        self.has_road_v = self.has_road_v or ((combined_edges_int & 0b0011) == 0b0011);
    }

    fn activate(self: *RoadUF, pos: brd.Position) void {
        const i: usize = @as(usize, @intCast(pos));
        self.active[i] = true;

        self.parent[i] = i;
        self.rank[i] = 0;
        self.edges[i] = edgeMaskForPos(pos);

        const e: u4 = @as(u4, @bitCast(self.edges[i]));
        self.has_road_h = self.has_road_h or ((e & 0b1100) == 0b1100);
        self.has_road_v = self.has_road_v or ((e & 0b0011) == 0b0011);
    }

    pub fn rebuildFromMask(self: *RoadUF, road_mask: brd.Bitboard) void {
        if (tracy_enable) {
            const z = tracy.trace(@src());
            defer z.end();
        }

        self.clear();

        // std.debug.print("Rebuilding RoadUF from mask {x}\n", .{road_mask});
        // brd.printBB(road_mask);

        for (0..brd.num_squares) |sq| {
            const pos: brd.Position = @as(brd.Position, @intCast(sq));
            // std.debug.print("Checking pos {}\n", .{sq});
            if ((road_mask & brd.getPositionBB(pos)) != 0) {
                // std.debug.print("Activating pos {}\n", .{sq});
                self.activate(pos);
            }
        }

        for (0..brd.num_squares) |sq| {
            if (!self.active[sq]) continue;

            const pos: brd.Position = @as(brd.Position, @intCast(sq));

            if (brd.nextPosition(pos, .East)) |nxt| {
                const nsq: usize = @as(usize, @intCast(nxt));
                if (self.active[nsq]) {
                    self.unionUF(sq, nsq);
                }
            }

            if (brd.nextPosition(pos, .North)) |nxt| {
                const nsq: usize = @as(usize, @intCast(nxt));
                if (self.active[nsq]) {
                    self.unionUF(sq, nsq);
                }
            }
        }
    }

    pub fn addPosIncremental(self: *RoadUF, pos: brd.Position, road_mask: brd.Bitboard) void {
        if (tracy_enable) {
            const z = tracy.trace(@src());
            defer z.end();
        }

        const i: usize = @as(usize, @intCast(pos));
        if (self.active[i]) return;

        self.activate(pos);

        if (brd.nextPosition(pos, .East)) |nxt| {
            const nsq: usize = @as(usize, @intCast(nxt));
            if ((road_mask & brd.getPositionBB(nxt)) != 0 and self.active[nsq]) {
                self.unionUF(i, nsq);
            }
        }

        if (brd.nextPosition(pos, .West)) |nxt| {
            const nsq: usize = @as(usize, @intCast(nxt));
            if ((road_mask & brd.getPositionBB(nxt)) != 0 and self.active[nsq]) {
                self.unionUF(i, nsq);
            }
        }

        if (brd.nextPosition(pos, .North)) |nxt| {
            const nsq: usize = @as(usize, @intCast(nxt));
            if ((road_mask & brd.getPositionBB(nxt)) != 0 and self.active[nsq]) {
                self.unionUF(i, nsq);
            }
        }

        if (brd.nextPosition(pos, .South)) |nxt| {
            const nsq: usize = @as(usize, @intCast(nxt));
            if ((road_mask & brd.getPositionBB(nxt)) != 0 and self.active[nsq]) {
                self.unionUF(i, nsq);
            }
        }
    }
};
