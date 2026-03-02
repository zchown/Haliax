const std = @import("std");
const brd = @import("board");

const PW = struct {
    early: i32,
    late: i32,

    inline fn at(self: PW, phase: u32) i32 {
        const diff = self.late - self.early;
        return self.early + @as(i32, @intCast((@as(i64, diff) *% @as(i64, @intCast(phase))) >> 8));
    }
};

inline fn pw(v: i32) PW {
    return .{ .early = v, .late = v };
}

const flat_count = PW{ .early = 120, .late = 250 };
const reserve_penalty = PW{ .early = -5, .late = -20 };

const tempo = PW{ .early = 15, .late = 5 };

const standing = PW{ .early = 150, .late = 50 };
const capstone = PW{ .early = 250, .late = 150 };

const center = PW{ .early = 12, .late = 3 };
const cap_center = PW{ .early = 30, .late = 8 };
const cap_edge_pen = PW{ .early = -30, .late = -5 };

const adjacency = PW{ .early = 12, .late = 6 };
const line_3 = PW{ .early = 18, .late = 8 };

const group_size = PW{ .early = 3, .late = 1 };
const edge_1 = PW{ .early = 25, .late = 10 };
const edge_2_adj = PW{ .early = 60, .late = 25 };
const edge_2_opp = pw(500);
const edge_3 = pw(500);
const span = PW{ .early = 15, .late = 5 };

const road_threat = PW{ .early = 300, .late = 200 };
const double_threat = PW{ .early = 500, .late = 350 };
const soft_threat = PW{ .early = 80, .late = 30 };

const support_flat = PW{ .early = 25, .late = 40 };
const captive_flat = PW{ .early = -30, .late = -50 };
const support_wall = PW{ .early = 30, .late = 35 };
const captive_wall = PW{ .early = -12, .late = -15 };
const support_cap = PW{ .early = 35, .late = 45 };
const captive_cap = PW{ .early = -15, .late = -20 };
const hard_cap = PW{ .early = 60, .late = 40 };
const hard_wall = PW{ .early = 30, .late = 20 };
const hard_flat = PW{ .early = 15, .late = 25 };

const overloaded_cap = PW{ .early = -80, .late = -120 };
const overloaded_wall = PW{ .early = -60, .late = -90 };
const overloaded_flat = PW{ .early = -100, .late = -150 };

const cap_mobility = PW{ .early = 8, .late = 4 };

const empty_control = PW{ .early = 15, .late = 8 };
const flat_control = PW{ .early = 8, .late = 30 };

const throw_mine = PW{ .early = 6, .late = 12 };
const throw_theirs = PW{ .early = 10, .late = 20 };
const throw_empty = PW{ .early = 8, .late = 5 };

const citadel = PW{ .early = 100, .late = 60 };

const phalanx = PW{ .early = 40, .late = 20 };

const fcd = PW{ .early = 30, .late = 120 };

const reserve_lead = PW{ .early = 0, .late = 15 };

const cap_psqt: [brd.num_squares]i32 = generateCapPSQT();

fn generateCapPSQT() [brd.num_squares]i32 {
    @setEvalBranchQuota(10000);
    var table: [brd.num_squares]i32 = undefined;
    const center_f: f64 = @as(f64, @floatFromInt(brd.board_size - 1)) / 2.0;
    const max_dist = center_f * 2.0;
    for (0..brd.num_squares) |pos| {
        const r: f64 = @as(f64, @floatFromInt(pos / brd.board_size));
        const c: f64 = @as(f64, @floatFromInt(pos % brd.board_size));
        const dist = @abs(r - center_f) + @abs(c - center_f);
        table[pos] = @as(i32, @intFromFloat(35.0 - 55.0 * dist / max_dist));
    }
    return table;
}

// Center ring masks
const num_rings = (brd.board_size + 1) / 2;
const rings: [num_rings]brd.Bitboard = generateRings();

fn generateRings() [num_rings]brd.Bitboard {
    @setEvalBranchQuota(10000);
    var computed: [num_rings]brd.Bitboard = undefined;
    var visited: brd.Bitboard = 0;
    var current: brd.Bitboard = 0;
    const center_local = brd.board_size / 2;

    if (brd.board_size % 2 == 0) {
        const c0 = center_local - 1;
        current |= @as(brd.Bitboard, 1) << @intCast(c0 * brd.board_size + c0);
        current |= @as(brd.Bitboard, 1) << @intCast(c0 * brd.board_size + center_local);
        current |= @as(brd.Bitboard, 1) << @intCast(center_local * brd.board_size + c0);
        current |= @as(brd.Bitboard, 1) << @intCast(center_local * brd.board_size + center_local);
    } else {
        current |= @as(brd.Bitboard, 1) << @intCast(center_local * brd.board_size + center_local);
    }
    computed[0] = current;
    visited = current;

    for (1..num_rings) |i| {
        var next: brd.Bitboard = 0;
        next |= current << brd.board_size;
        next |= current >> brd.board_size;
        next |= (current << 1) & ~brd.column_masks[0];
        next |= (current >> 1) & not_right_col;
        next &= brd.board_mask & ~visited;
        computed[i] = next;
        visited |= next;
        current = next;
    }
    return computed;
}

const edge_mask: brd.Bitboard = blk: {
    var m: brd.Bitboard = 0;
    m |= brd.row_masks[0];
    m |= brd.row_masks[brd.board_size - 1];
    m |= brd.column_masks[0];
    m |= brd.column_masks[brd.board_size - 1];
    break :blk m;
};

const not_right_col: brd.Bitboard = ~brd.column_masks[brd.board_size - 1] & brd.board_mask;
const not_left_col: brd.Bitboard = ~brd.column_masks[0] & brd.board_mask;

const ColorBBs = struct {
    control: brd.Bitboard,
    flats: brd.Bitboard,
    walls: brd.Bitboard,
    caps: brd.Bitboard,
    roads: brd.Bitboard, // flats + caps
    opp_control: brd.Bitboard,
    opp_flats: brd.Bitboard,
};

inline fn colorBBs(board: *const brd.Board, color: brd.Color) ColorBBs {
    const my = if (color == .White) board.white_control else board.black_control;
    const op = if (color == .White) board.black_control else board.white_control;
    const flats = my & ~board.standing_stones & ~board.capstones;
    const walls = my & board.standing_stones;
    const caps = my & board.capstones;
    return .{
        .control = my,
        .flats = flats,
        .walls = walls,
        .caps = caps,
        .roads = flats | caps,
        .opp_control = op,
        .opp_flats = op & ~board.standing_stones & ~board.capstones,
    };
}

pub fn evaluate(board: *const brd.Board) i32 {
    const total_initial: u32 = (brd.stone_count + brd.capstone_count) * 2;
    const w_remaining: u32 = @intCast(board.white_stones_remaining + board.white_capstones_remaining);
    const b_remaining: u32 = @intCast(board.black_stones_remaining + board.black_capstones_remaining);
    const total_used: u32 = total_initial - w_remaining - b_remaining;

    const occ_count = brd.countBits(board.white_control | board.black_control);
    const fill_frac = (occ_count * 256) / @as(u32, brd.num_squares);
    const reserve_frac = if (total_initial > 0)
        (total_used * 256) / total_initial
    else
        @as(u32, 256);
    const phase: u32 = @min(256, @max(fill_frac, reserve_frac));

    const w = colorBBs(board, .White);
    const b = colorBBs(board, .Black);

    const score_white = evalColor(board, .White, w, phase);
    const score_black = evalColor(board, .Black, b, phase);

    const citadel_score = evalCitadels(w.roads, b.roads, phase);
    const phalanx_score = evalPhalanx(w, b, phase);
    const influence_score = evalInfluence(w, b, board.empty_squares, phase);
    const fcd_score = evalFCD(w.flats, b.flats, phase);
    const reserve_score = evalReserveAsymmetry(board, phase);

    var total = (score_white - score_black) +
        citadel_score + phalanx_score + influence_score +
        fcd_score + reserve_score;

    if (board.to_move == .Black) {
        total = -total;
    }
    total += tempo.at(phase);

    return total;
}

fn evalColor(board: *const brd.Board, color: brd.Color, bb: ColorBBs, phase: u32) i32 {
    var score: i32 = 0;

    score += @as(i32, @intCast(brd.countBits(bb.flats))) * flat_count.at(phase);
    score += @as(i32, @intCast(brd.countBits(bb.walls))) * standing.at(phase);
    score += @as(i32, @intCast(brd.countBits(bb.caps))) * capstone.at(phase);

    const reserves: i32 = @intCast(if (color == .White)
        board.white_stones_remaining
    else
        board.black_stones_remaining);
    score += reserves * reserve_penalty.at(phase);

    score += @as(i32, @intCast(brd.countBits(bb.flats & rings[0]))) * center.at(phase);
    if (comptime num_rings > 1) {
        score += @as(i32, @intCast(brd.countBits(bb.flats & rings[1]))) * @divTrunc(center.at(phase), 2);
    }

    if (bb.caps != 0) {
        const cap_pos: brd.Position = brd.getLSB(bb.caps);
        score += cap_psqt[cap_pos];
        if ((bb.caps & rings[0]) != 0) score += cap_center.at(phase);
        if ((bb.caps & edge_mask) != 0) score += cap_edge_pen.at(phase);
        score += evalCapMobility(board, cap_pos) * cap_mobility.at(phase);
    }

    {
        const shift_right = (bb.roads >> 1) & not_right_col;
        const shift_up = bb.roads >> brd.board_size;

        const adj_h = bb.roads & shift_right;
        const adj_v = bb.roads & shift_up;

        const line_h = adj_h & ((adj_h >> 1) & not_right_col);
        const line_v = adj_v & (adj_v >> brd.board_size);

        score += @as(i32, @intCast(brd.countBits(adj_h) + brd.countBits(adj_v))) * adjacency.at(phase);
        score += @as(i32, @intCast(brd.countBits(line_h) + brd.countBits(line_v))) * line_3.at(phase);
    }

    score += evalGroups(bb.roads, phase);

    score += evalRoadThreats(bb.roads, board.empty_squares, phase);

    score += evalStacks(board, color, phase);

    score += evalThrowPotential(board, color, bb, phase);

    return score;
}

// flood-fill connected components
fn evalGroups(road_bb: brd.Bitboard, phase: u32) i32 {
    var score: i32 = 0;
    var remaining = road_bb;

    while (remaining != 0) {
        // Isolate LSB as seed
        const seed: brd.Bitboard = remaining & (~remaining +% 1);
        var group = seed;
        var frontier = seed;

        while (frontier != 0) {
            const expand = growMasked(frontier, remaining & ~group);
            group |= expand;
            frontier = expand;
        }
        remaining ^= group; // clear entire group at once

        const size = brd.countBits(group);
        if (size < 2) continue;

        score += @as(i32, @intCast(size)) * group_size.at(phase);

        // Edge analysis 
        const t_top = (group & brd.row_masks[brd.board_size - 1]) != 0;
        const t_bot = (group & brd.row_masks[0]) != 0;
        const t_left = (group & brd.column_masks[0]) != 0;
        const t_right = (group & brd.column_masks[brd.board_size - 1]) != 0;
        const edges: u32 = @intFromBool(t_top) + @intFromBool(t_bot) +
            @intFromBool(t_left) + @intFromBool(t_right);

        if (edges >= 3) {
            score += edge_3.at(phase);
        } else if (edges == 2) {
            if ((t_top and t_bot) or (t_left and t_right)) {
                score += edge_2_opp.at(phase);
            } else {
                score += edge_2_adj.at(phase);
            }
        } else if (edges == 1) {
            score += edge_1.at(phase);
        }

        // Span via row/col projection
        var row_occ: u32 = 0;
        var col_occ: u32 = 0;
        inline for (0..brd.board_size) |r| {
            if ((group & brd.row_masks[r]) != 0) row_occ += 1;
        }
        inline for (0..brd.board_size) |c| {
            if ((group & brd.column_masks[c]) != 0) col_occ += 1;
        }
        score += @as(i32, @intCast(@max(row_occ, col_occ))) * span.at(phase);
    }

    return score;
}

fn evalRoadThreats(road_bb: brd.Bitboard, empty: brd.Bitboard, phase: u32) i32 {
    var threat_squares: brd.Bitboard = 0;
    var soft_squares: brd.Bitboard = 0;

    // Horizontal
    {
        const left_flood = floodFill(road_bb, road_bb & brd.column_masks[0]);
        const right_flood = floodFill(road_bb, road_bb & brd.column_masks[brd.board_size - 1]);

        if (left_flood != 0 and right_flood != 0) {
            threat_squares |= grow(left_flood) & grow(right_flood) & empty;
        }
        if (left_flood != 0) soft_squares |= softFromFlood(left_flood, empty);
        if (right_flood != 0) soft_squares |= softFromFlood(right_flood, empty);
    }

    // Vertical
    {
        const bot_flood = floodFill(road_bb, road_bb & brd.row_masks[0]);
        const top_flood = floodFill(road_bb, road_bb & brd.row_masks[brd.board_size - 1]);

        if (bot_flood != 0 and top_flood != 0) {
            threat_squares |= grow(bot_flood) & grow(top_flood) & empty;
        }
        if (bot_flood != 0) soft_squares |= softFromFlood(bot_flood, empty);
        if (top_flood != 0) soft_squares |= softFromFlood(top_flood, empty);
    }

    soft_squares &= ~threat_squares; // no double-counting

    const threat_count = brd.countBits(threat_squares);
    var score: i32 = 0;
    if (threat_count >= 2) {
        score += double_threat.at(phase);
    } else if (threat_count == 1) {
        score += road_threat.at(phase);
    }
    score += @as(i32, @intCast(brd.countBits(soft_squares))) * soft_threat.at(phase);

    return score;
}

// STACK STRUCTURE  (captives, support, hard-top, overloading)
fn evalStacks(board: *const brd.Board, color: brd.Color, phase: u32) i32 {
    var score: i32 = 0;
    const my_control = if (color == .White) board.white_control else board.black_control;

    var iter_bb = my_control;
    while (iter_bb != 0) {
        const pos: brd.Position = brd.getLSB(iter_bb);
        iter_bb &= iter_bb - 1; // clear LSB

        const sq = &board.squares[pos];
        if (sq.len <= 1) continue;

        const top_piece = sq.top().?;

        const s_weight: i32 = switch (top_piece.stone_type) {
            .Flat => support_flat.at(phase),
            .Standing => support_wall.at(phase),
            .Capstone => support_cap.at(phase),
        };
        const c_weight: i32 = switch (top_piece.stone_type) {
            .Flat => captive_flat.at(phase),
            .Standing => captive_wall.at(phase),
            .Capstone => captive_cap.at(phase),
        };
        const hard_bonus: i32 = switch (top_piece.stone_type) {
            .Flat => hard_flat.at(phase),
            .Standing => hard_wall.at(phase),
            .Capstone => hard_cap.at(phase),
        };
        const overload_pen: i32 = switch (top_piece.stone_type) {
            .Flat => overloaded_flat.at(phase),
            .Standing => overloaded_wall.at(phase),
            .Capstone => overloaded_cap.at(phase),
        };

        // Hard-top: friendly stone immediately under top
        const under_top = sq.stack[sq.len - 2].?;
        if (under_top.color == color) {
            score += hard_bonus;
        }

        // Scan stack below top (limited depth for relevance)
        var continuous_opponent: u32 = 0;
        var chain_broken = false;
        const scan_depth = @min(sq.len - 1, brd.max_pickup);
        var idx: usize = sq.len - 2;
        for (0..scan_depth) |_| {
            const piece = sq.stack[idx].?;
            if (piece.color == color) {
                score += s_weight;
                chain_broken = true;
            } else {
                score += c_weight;
                if (!chain_broken) continuous_opponent += 1;
            }
            if (idx == 0) break;
            idx -= 1;
        }

        if (continuous_opponent >= brd.max_pickup) {
            score += overload_pen;
        }
    }

    return score;
}

fn evalCapMobility(board: *const brd.Board, cap_pos: brd.Position) i32 {
    const height = board.squares[cap_pos].len;
    if (height < 1) return 0;

    const reach = @min(height, brd.max_pickup);
    var mobility: i32 = 0;

    inline for ([_]brd.Direction{ .North, .South, .East, .West }) |dir| {
        var pos = cap_pos;
        for (0..reach) |_| {
            const next = brd.nextPosition(pos, dir) orelse break;
            const target_bit = brd.getPositionBB(next);

            if ((target_bit & board.capstones) != 0) break;
            if ((target_bit & board.standing_stones) != 0) {
                mobility += 1; // can flatten wall
                break;
            }
            mobility += 1;
            pos = next;
        }
    }

    return mobility;
}

fn evalThrowPotential(board: *const brd.Board, color: brd.Color, bb: ColorBBs, phase: u32) i32 {
    var score: i32 = 0;

    var iter = bb.control;
    while (iter != 0) {
        const pos: brd.Position = brd.getLSB(iter);
        iter &= iter - 1;

        const sq = &board.squares[pos];
        if (sq.len < 2) continue;

        // Quick count of friendly stones below top using Square's tracked counts
        const my_total: usize = if (color == .White) sq.white_count else sq.black_count;
        const top_is_mine = sq.top().?.color == color;
        const friendly_below = my_total - @as(usize, @intFromBool(top_is_mine));
        if (friendly_below == 0) continue;

        const height = @min(sq.len, brd.max_pickup);
        const top_is_cap = sq.top().?.stone_type == .Capstone;

        inline for ([_]brd.Direction{ .North, .South, .East, .West }) |dir| {
            var p = pos;
            for (0..height) |dist| {
                const next = brd.nextPosition(p, dir) orelse break;
                const target_bit = brd.getPositionBB(next);

                if ((target_bit & board.capstones) != 0) break;
                if ((target_bit & board.standing_stones) != 0) {
                    if (top_is_cap and dist + 1 == height) {
                        if ((target_bit & bb.opp_flats) != 0) {
                            score += throw_theirs.at(phase);
                        }
                    }
                    break;
                }

                if ((target_bit & bb.opp_flats) != 0) {
                    score += throw_theirs.at(phase);
                } else if ((target_bit & bb.flats) != 0) {
                    score += throw_mine.at(phase);
                } else if ((target_bit & board.empty_squares) != 0) {
                    score += throw_empty.at(phase);
                }

                p = next;
            }
        }
    }

    return score;
}

// CITADEL (2x2 road-stone blocks) 
fn evalCitadels(w_roads: brd.Bitboard, b_roads: brd.Bitboard, phase: u32) i32 {
    const w_count = countCitadels(w_roads);
    const b_count = countCitadels(b_roads);
    return (@as(i32, @intCast(w_count)) - @as(i32, @intCast(b_count))) * citadel.at(phase);
}

inline fn countCitadels(roads: brd.Bitboard) u32 {
    const h_pair = roads & ((roads >> 1) & not_right_col);
    return brd.countBits(h_pair & (h_pair >> brd.board_size));
}

fn evalPhalanx(w: ColorBBs, b: ColorBBs, phase: u32) i32 {
    const w_nobles = w.walls | w.caps;
    const b_nobles = b.walls | b.caps;
    const w_count = countDiagPairs(w_nobles);
    const b_count = countDiagPairs(b_nobles);
    return (@as(i32, @intCast(w_count)) - @as(i32, @intCast(b_count))) * phalanx.at(phase);
}

inline fn countDiagPairs(nobles: brd.Bitboard) u32 {
    const ur = (nobles << (brd.board_size + 1)) & not_left_col & brd.board_mask;
    const ul = (nobles << (brd.board_size - 1)) & not_right_col & brd.board_mask;
    return brd.countBits(nobles & ur) + brd.countBits(nobles & ul);
}

fn evalInfluence(w: ColorBBs, b: ColorBBs, empty: brd.Bitboard, phase: u32) i32 {
    const w_inf = grow(w.flats | w.caps);
    const b_inf = grow(b.flats | b.caps);
    const w_only = w_inf & ~b_inf;
    const b_only = b_inf & ~w_inf;

    var score: i32 = 0;
    score += (@as(i32, @intCast(brd.countBits(w_only & empty))) -
        @as(i32, @intCast(brd.countBits(b_only & empty)))) * empty_control.at(phase);
    score += (@as(i32, @intCast(brd.countBits(w_only & b.flats))) -
        @as(i32, @intCast(brd.countBits(b_only & w.flats)))) * flat_control.at(phase);
    return score;
}

inline fn evalFCD(w_flats: brd.Bitboard, b_flats: brd.Bitboard, phase: u32) i32 {
    const wf: i32 = @intCast(brd.countBits(w_flats));
    const bf: i32 = @intCast(brd.countBits(b_flats));
    const komi_int: i32 = @intFromFloat(brd.komi);
    return (wf - bf - komi_int) * fcd.at(phase);
}

inline fn evalReserveAsymmetry(board: *const brd.Board, phase: u32) i32 {
    const w_res: i32 = @intCast(board.white_stones_remaining + board.white_capstones_remaining);
    const b_res: i32 = @intCast(board.black_stones_remaining + board.black_capstones_remaining);
    return (b_res - w_res) * reserve_lead.at(phase);
}

// Grow bitboard by 1 orthogonal step in all directions
inline fn grow(bb: brd.Bitboard) brd.Bitboard {
    return (bb |
        ((bb << 1) & not_left_col) |
        ((bb >> 1) & not_right_col) |
        (bb << brd.board_size) |
        (bb >> brd.board_size)) & brd.board_mask;
}

// Grow bitboard, but only into squares present in allowed
inline fn growMasked(bb: brd.Bitboard, allowed: brd.Bitboard) brd.Bitboard {
    return (((bb << 1) & not_left_col) |
        ((bb >> 1) & not_right_col) |
        (bb << brd.board_size) |
        (bb >> brd.board_size)) & allowed & brd.board_mask;
}

// Flood-fill through mask from seed
inline fn floodFill(mask: brd.Bitboard, seed: brd.Bitboard) brd.Bitboard {
    var flood = seed & mask;
    if (flood == 0) return 0;
    var prev: brd.Bitboard = 0;
    while (flood != prev) {
        prev = flood;
        flood |= grow(flood) & mask;
    }
    return flood;
}

// Empty squares adjacent to a flood spanning >= board_size-1 in any axis
fn softFromFlood(flood: brd.Bitboard, empty: brd.Bitboard) brd.Bitboard {
    var col_count: u32 = 0;
    var row_count: u32 = 0;
    inline for (0..brd.board_size) |c| {
        if ((flood & brd.column_masks[c]) != 0) col_count += 1;
    }
    inline for (0..brd.board_size) |r| {
        if ((flood & brd.row_masks[r]) != 0) row_count += 1;
    }
    if (col_count >= brd.board_size - 1 or row_count >= brd.board_size - 1) {
        return grow(flood) & empty;
    }
    return 0;
}
