const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const onnx = @import("onnxrt");

fn softmaxInto(out: []f32, logits: []const f32) void {
    var maxv: f32 = -std.math.inf(f32);
    for (logits) |x| {
        if (x > maxv) maxv = x;
    }

    var sum: f32 = 0;
    for (logits, 0..) |x, i| {
        const e = std.math.exp(x - maxv);
        out[i] = e;
        sum += e;
    }
    if (sum <= 0) {
        const u = 1.0 / @as(f32, @floatFromInt(out.len));
        for (out) |*p| p.* = u;
        return;
    }
    const inv = 1.0 / sum;
    for (out) |*p| p.* *= inv;
}

fn clampPickupIdx(moved: usize) usize {
    var m = moved;
    if (m < 1) m = 1;
    if (m > brd.max_pickup) m = brd.max_pickup;
    return m - 1; // 0..5
}

fn slideLenIdx(pattern: u8) ?usize {
    const ones: u8 = @intCast(@popCount(pattern));
    if (ones < 1 or ones > 6) return null;
    return ones - 1; // 0..5
}

pub const NNEval = struct {
    allocator: std.mem.Allocator,
    runner: onnx.OnnxRunner,

    // scratch buffers (logits and probs)
    logits_place_pos: [36]f32 = undefined,
    logits_place_type: [3]f32 = undefined,
    logits_slide_from: [36]f32 = undefined,
    logits_slide_dir: [4]f32 = undefined,
    logits_slide_pickup: [6]f32 = undefined,
    logits_slide_len: [6]f32 = undefined,

    prob_place_pos: [36]f32 = undefined,
    prob_place_type: [3]f32 = undefined,
    prob_slide_from: [36]f32 = undefined,
    prob_slide_dir: [4]f32 = undefined,
    prob_slide_pickup: [6]f32 = undefined,
    prob_slide_len: [6]f32 = undefined,

    pub fn init(allocator: std.mem.Allocator, model_path: []const u8) !NNEval {
        return .{
            .allocator = allocator,
            .runner = try onnx.OnnxRunner.init(allocator, model_path),
        };
    }

    pub fn deinit(self: *NNEval) void {
        self.runner.deinit();
    }

    /// Returns value in [-1,1] from perspective of side to move at this node,
    /// and fills priors_out aligned to `moves`.
    pub fn eval(self: *NNEval, board: *const brd.Board, moves: []const brd.Move, priors_out: []f32) f32 {
        if (priors_out.len != moves.len) {
            // Caller error; fail safe.
            if (priors_out.len > 0) {
                const u = 1.0 / @as(f32, @floatFromInt(priors_out.len));
                for (priors_out) |*p| p.* = u;
            }
            return 0.0;
        }

        // Get CHW input from the side-to-move vector.
        const src = if (board.to_move == .White) board.white_vector.data else board.black_vector.data;
        const channels_in_usize = src.len / brd.num_squares;
        const channels_in: i64 = @intCast(channels_in_usize);

        const value = self.runner.run(
            channels_in,
            &src,
            self.logits_place_pos[0..],
            self.logits_place_type[0..],
            self.logits_slide_from[0..],
            self.logits_slide_dir[0..],
            self.logits_slide_pickup[0..],
            self.logits_slide_len[0..],
        ) catch {
            // Fail-safe: uniform priors, 0 value
            if (priors_out.len > 0) {
                const u = 1.0 / @as(f32, @floatFromInt(priors_out.len));
                for (priors_out) |*p| p.* = u;
            }
            return 0.0;
        };

        // Convert logits -> probabilities per head
        softmaxInto(self.prob_place_pos[0..], self.logits_place_pos[0..]);
        softmaxInto(self.prob_place_type[0..], self.logits_place_type[0..]);
        softmaxInto(self.prob_slide_from[0..], self.logits_slide_from[0..]);
        softmaxInto(self.prob_slide_dir[0..], self.logits_slide_dir[0..]);
        softmaxInto(self.prob_slide_pickup[0..], self.logits_slide_pickup[0..]);
        softmaxInto(self.prob_slide_len[0..], self.logits_slide_len[0..]);

        // Map move -> prior probability
        for (moves, 0..) |mv, i| {
            const pos_idx: usize = @intCast(mv.position);
            var p: f32 = 0.0;

            // Place
            if (mv.pattern == 0) {
                const t: usize = @intCast(mv.flag);
                if (pos_idx < 36 and t < 3) {
                    p = self.prob_place_pos[pos_idx] * self.prob_place_type[t];
                }
            } else {
                // Slide
                const dir: usize = @intCast(mv.flag);
                const pickup_i = clampPickupIdx(mv.movedStones());
                const len_i = slideLenIdx(mv.pattern);
                if (pos_idx < 36 and dir < 4 and pickup_i < 6 and len_i != null) {
                    p = self.prob_slide_from[pos_idx] * self.prob_slide_dir[dir] * self.prob_slide_pickup[pickup_i] * self.prob_slide_len[len_i.?];
                }
            }

            priors_out[i] = p;
        }

        // Normalize
        var sum: f32 = 0.0;
        for (priors_out) |*p| {
            if (p.* < 0) p.* = 0;
            sum += p.*;
        }
        if (sum <= 0.0) {
            if (priors_out.len > 0) {
                const u = 1.0 / @as(f32, @floatFromInt(priors_out.len));
                for (priors_out) |*p| p.* = u;
            }
        } else {
            const inv = 1.0 / sum;
            for (priors_out) |*p| p.* *= inv;
        }

        return value;
    }
};

