const std = @import("std");
const brd = @import("board");
const road = @import("road");

const w_flat = 175;
const w_reserve = -13;
const w_tempo = 10;

const w_adjacency = 9;
const w_line = 7;

const w_support_flat = 30;
const w_captive_flat = -40;
const w_support_wall = 35;
const w_captive_wall = -15;
const w_support_cap = 40;
const w_captive_cap = -20;


// Per-stone bonus for being part of a connected group of 2+
const w_group_size = 5;

// Bonus by how many board edges a connected component touches.
// A component touching 2 *opposite* edges is already a completed road
// (game over before eval), so edge_2_opp is practically unreachable
// but kept for safety.
const w_edge_1 = 20;
const w_edge_2_adj = 50;
const w_edge_2_opp = 120; // road
const w_edge_3 = 180; // road

// Per-row (or col) of span — rewards groups that stretch far
const w_span = 12;

// Bonus when an empty square would complete a road if a flat were placed
const w_road_threat = 250;

// Extra bonus when 2+ distinct road-completing squares exist (fork)
const w_double_threat = 400;

// Bonus when placing a flat on an empty square would create a group
// spanning (board_size - 1) rows or cols (one step from road)
const w_soft_threat = 60;

const w_rings = [_]i32{ 2, 8, -5 };

const cap_psqt = [_]i32{
    -20, -5, -5, -5, -5, -20,
    -5,  10, 18, 18, 10, -5,
    -5,  18, 35, 35, 18, -5,
    -5,  18, 35, 35, 18, -5,
    -5,  10, 18, 18, 10, -5,
    -20, -5, -5, -5, -5, -20,
};

const rings = generateRings();

fn generateRings() [(brd.board_size + 1) / 2]brd.Bitboard {
    @setEvalBranchQuota(10000);
    const num_rings = (brd.board_size + 1) / 2;
    var computed_rings: [num_rings]brd.Bitboard = undefined;
    var visited: brd.Bitboard = 0;

    var current_ring: brd.Bitboard = 0;
    const center = brd.board_size / 2;

    if (brd.board_size % 2 == 0) {
        const c0 = center - 1;
        const c1 = center;
        current_ring |= (@as(brd.Bitboard, 1) << @intCast(c0 * brd.board_size + c0));
        current_ring |= (@as(brd.Bitboard, 1) << @intCast(c0 * brd.board_size + c1));
        current_ring |= (@as(brd.Bitboard, 1) << @intCast(c1 * brd.board_size + c0));
        current_ring |= (@as(brd.Bitboard, 1) << @intCast(c1 * brd.board_size + c1));
    } else {
        current_ring |= (@as(brd.Bitboard, 1) << @intCast(center * brd.board_size + center));
    }

    computed_rings[0] = current_ring;
    visited = current_ring;

    for (1..num_rings) |i| {
        var next: brd.Bitboard = 0;
        next |= (current_ring << brd.board_size);
        next |= (current_ring >> brd.board_size);
        const right_edge = brd.column_masks[brd.board_size - 1];
        next |= ((current_ring & ~right_edge) << 1);
        const left_edge = brd.column_masks[0];
        next |= ((current_ring & ~left_edge) >> 1);
        next &= brd.board_mask;
        next &= ~visited;
        computed_rings[i] = next;
        visited |= next;
        current_ring = next;
    }

    return computed_rings;
}


inline fn ufRoot(parent: *const [brd.num_squares]usize, i: usize) usize {
    var x = i;
    while (x != parent[x]) {
        x = parent[x];
    }
    return x;
}

inline fn edgeBits(sq: usize) u4 {
    const row = sq / brd.board_size;
    const col = sq % brd.board_size;
    var mask: u4 = 0;
    if (row == brd.board_size - 1) mask |= 0b0001; // north
    if (row == 0) mask |= 0b0010; // south
    if (col == brd.board_size - 1) mask |= 0b0100; // east
    if (col == 0) mask |= 0b1000; // west
    return mask;
}

inline fn spansVertical(edges: u4) bool {
    return (edges & 0b0011) == 0b0011;
}

inline fn spansHorizontal(edges: u4) bool {
    return (edges & 0b1100) == 0b1100;
}

inline fn edgeCount(edges: u4) u32 {
    return @popCount(edges);
}

inline fn oppositeEdges(edges: u4) bool {
    return spansVertical(edges) or spansHorizontal(edges);
}

pub fn evaluate(board: *brd.Board) i32 {
    const score_white = evalColor(board, .White);
    const score_black = evalColor(board, .Black);
    const ring_score = evalRings(board);
    const road_white = evalRoadConnectivity(board, .White);
    const road_black = evalRoadConnectivity(board, .Black);

    var total = (score_white - score_black) + ring_score + (road_white - road_black);

    if (board.to_move == .Black) {
        total = -total;
    }
    total += w_tempo;
    return total;
}

fn evalColor(board: *brd.Board, color: brd.Color) i32 {
    var score: i32 = 0;

    const my_control = if (color == .White) board.white_control else board.black_control;
    const my_flats = my_control & ~board.standing_stones & ~board.capstones;
    const my_roads = my_control & ~board.standing_stones; // flats + caps

    // 1. Material (flat count
    var flat_count = @as(i32, @intCast(brd.countBits(my_flats)));
    if (color == .Black) {
        flat_count += @as(i32, @intFromFloat(brd.komi));
    }
    score += flat_count * w_flat;

    // 2. Reserves 
    const reserves = if (color == .White) board.white_stones_remaining else board.black_stones_remaining;
    score += @as(i32, @intCast(reserves)) * w_reserve;

    // 3. Connectivity 
    const left_shift = (my_roads >> 1) & ~brd.column_masks[brd.board_size - 1];
    const down_shift = (my_roads >> brd.board_size) & ~brd.row_masks[brd.board_size - 1];

    const adj_horz = my_roads & left_shift;
    const adj_vert = my_roads & down_shift;

    const line_horz = adj_horz & (adj_horz >> 1) & ~brd.column_masks[brd.board_size - 1];
    const line_vert = adj_vert & (adj_vert >> brd.board_size) & ~brd.row_masks[brd.board_size - 1];

    const adj_count = brd.countBits(adj_horz) + brd.countBits(adj_vert);
    const line_count = brd.countBits(line_horz) + brd.countBits(line_vert);

    score += @as(i32, @intCast(adj_count)) * w_adjacency;
    score += @as(i32, @intCast(line_count)) * w_line;

    // 4. Per-square: capstone PSQT + stack structure
    var iter_bb = my_control;
    while (iter_bb != 0) {
        const pos = brd.getLSB(iter_bb);
        brd.clearBit(&iter_bb, pos);

        // Capstone PSQT + isolation
        if (brd.getBit(board.capstones, pos)) {
            score += cap_psqt[pos];

            const all_occ = board.white_control | board.black_control;
            const obstacles = all_occ & ~my_flats;

            var adj_mask: brd.Bitboard = 0;
            const p_bb = brd.getPositionBB(pos);
            if ((p_bb & ~brd.column_masks[0]) != 0) adj_mask |= (p_bb >> 1);
            if ((p_bb & ~brd.column_masks[brd.board_size - 1]) != 0) adj_mask |= (p_bb << 1);
            if ((p_bb & ~brd.row_masks[0]) != 0) adj_mask |= (p_bb >> brd.board_size);
            if ((p_bb & ~brd.row_masks[brd.board_size - 1]) != 0) adj_mask |= (p_bb << brd.board_size);

            if ((adj_mask & obstacles) == 0) {
                score -= 50;
            }
        }

        // Stack captive / support scoring
        const sq = &board.squares[pos];
        if (sq.len <= 1) continue;

        const top_piece = sq.top().?;
        var s_weight: i32 = 0;
        var c_weight: i32 = 0;

        switch (top_piece.stone_type) {
            .Flat => {
                s_weight = w_support_flat;
                c_weight = w_captive_flat;
            },
            .Standing => {
                s_weight = w_support_wall;
                c_weight = w_captive_wall;
            },
            .Capstone => {
                s_weight = w_support_cap;
                c_weight = w_captive_cap;
            },
        }

        var depth: usize = 0;
        var i: usize = sq.len - 1;
        while (i > 0) : (i -= 1) {
            if (depth >= 7) break;
            depth += 1;

            const piece_below = sq.stack[i - 1].?;
            if (piece_below.color == color) {
                score += s_weight;
            } else {
                score += c_weight;
            }
        }
    }

    return score;
}

fn evalRings(board: *brd.Board) i32 {
    var score: i32 = 0;

    const w_flats = board.white_control & ~board.standing_stones & ~board.capstones;
    const b_flats = board.black_control & ~board.standing_stones & ~board.capstones;

    for (rings, 0..) |ring_mask, i| {
        if (i >= w_rings.len) break;

        const w_count = @as(i32, @intCast(brd.countBits(w_flats & ring_mask)));
        const b_count = @as(i32, @intCast(brd.countBits(b_flats & ring_mask)));

        score += (w_count - b_count) * w_rings[i];
    }

    return score;
}

fn evalRoadConnectivity(board: *brd.Board, color: brd.Color) i32 {
    const uf = if (color == .White) &board.white_road_uf else &board.black_road_uf;
    var score: i32 = 0;

    // Per-root aggregated data
    var root_seen: [brd.num_squares]bool = [_]bool{false} ** brd.num_squares;
    var comp_size: [brd.num_squares]i32 = [_]i32{0} ** brd.num_squares;
    var comp_min_row: [brd.num_squares]usize = [_]usize{brd.board_size} ** brd.num_squares;
    var comp_max_row: [brd.num_squares]usize = [_]usize{0} ** brd.num_squares;
    var comp_min_col: [brd.num_squares]usize = [_]usize{brd.board_size} ** brd.num_squares;
    var comp_max_col: [brd.num_squares]usize = [_]usize{0} ** brd.num_squares;

    // Gather per-component stats in one pass
    for (0..brd.num_squares) |sq| {
        if (!uf.active[sq]) continue;

        const root = ufRoot(&uf.parent, sq);
        comp_size[root] += 1;

        const row = sq / brd.board_size;
        const col = sq % brd.board_size;
        comp_min_row[root] = @min(comp_min_row[root], row);
        comp_max_row[root] = @max(comp_max_row[root], row);
        comp_min_col[root] = @min(comp_min_col[root], col);
        comp_max_col[root] = @max(comp_max_col[root], col);
    }

    // Score each component once
    for (0..brd.num_squares) |sq| {
        if (!uf.active[sq]) continue;

        const root = ufRoot(&uf.parent, sq);
        if (root_seen[root]) continue;
        root_seen[root] = true;

        const edges: u4 = @bitCast(uf.edges[root]);
        const ec = edgeCount(edges);
        const size = comp_size[root];

        // Group size bonus (only for connected groups, not singletons)
        if (size >= 2) {
            score += size * w_group_size;
        }

        // Edge-touch bonus
        switch (ec) {
            1 => score += w_edge_1,
            2 => {
                // Two opposite edges = completed road (shouldn't reach eval),
                // but handle gracefully in case of a race.
                if (oppositeEdges(edges)) {
                    score += w_edge_2_opp;
                } else {
                    score += w_edge_2_adj;
                }
            },
            3 => score += w_edge_3,
            else => {},
        }

        // Span bonus — how far the group stretches across the board
        const row_span = comp_max_row[root] - comp_min_row[root] + 1;
        const col_span = comp_max_col[root] - comp_min_col[root] + 1;
        const best_span = @max(row_span, col_span);

        // Only award span bonus for groups that stretch meaningfully
        if (best_span >= 2) {
            score += @as(i32, @intCast(best_span)) * w_span;
        }
    }

    // Phase 2: Road threats — empty squares where placing a flat
    //          would complete a road through that square.
    //
    // Logic: placing on an empty square connects all adjacent
    // friendly components through that square.  We OR all their
    // edge-masks together with the square's own edge-bits and
    // check whether opposite edges are spanned.

    var threat_count: i32 = 0;
    var soft_threat_count: i32 = 0;

    var empty = board.empty_squares;
    while (empty != 0) {
        const pos = brd.getLSB(empty);
        brd.clearBit(&empty, pos);
        const sq_idx: usize = @intCast(pos);

        var combined: u4 = edgeBits(sq_idx);

        // Also track max span that would result (approximate via row/col extent)
        var min_r: usize = sq_idx / brd.board_size;
        var max_r: usize = min_r;
        var min_c: usize = sq_idx % brd.board_size;
        var max_c: usize = min_c;

        // Check all 4 neighbours
        const neighbours = [_]?brd.Position{
            brd.nextPosition(pos, .North),
            brd.nextPosition(pos, .South),
            brd.nextPosition(pos, .East),
            brd.nextPosition(pos, .West),
        };

        for (neighbours) |maybe_nxt| {
            if (maybe_nxt) |nxt| {
                const nsq: usize = @intCast(nxt);
                if (uf.active[nsq]) {
                    const root = ufRoot(&uf.parent, nsq);
                    combined |= @as(u4, @bitCast(uf.edges[root]));
                    min_r = @min(min_r, comp_min_row[root]);
                    max_r = @max(max_r, comp_max_row[root]);
                    min_c = @min(min_c, comp_min_col[root]);
                    max_c = @max(max_c, comp_max_col[root]);
                }
            }
        }

        // Would placing here complete a road?
        if (spansVertical(combined) or spansHorizontal(combined)) {
            threat_count += 1;
        }
        // Would it create a group spanning (board_size - 1)?
        else {
            const new_row_span = max_r - min_r + 1;
            const new_col_span = max_c - min_c + 1;
            if (new_row_span >= brd.board_size - 1 or new_col_span >= brd.board_size - 1) {
                soft_threat_count += 1;
            }
        }
    }

    score += threat_count * w_road_threat;
    score += soft_threat_count * w_soft_threat;

    // Fork bonus: multiple road-completing squares are very hard to defend
    if (threat_count >= 2) {
        score += w_double_threat;
    }

    return score;
}
