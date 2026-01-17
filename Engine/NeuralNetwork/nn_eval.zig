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

    /// Matches tree_search.EvalFn signature:
    /// returns value in [-1,1] from perspective of side to move at this node,
    /// and fills priors_out per legal move order (generated in tree_search.expand()).
    pub fn eval(self: *NNEval, board: *const brd.Board, priors_out: []f32) f32 {
        // Make sure vectors are up to date (caller usually keeps them updated,
        // but safe if you want: you’d need a mutable board; so we assume updated.)

        // Get CHW input from the side-to-move vector.
        const src = if (board.to_move == .White) board.white_vector.data else board.black_vector.data;
        const channels_in_usize = src.len / brd.num_squares;
        const channels_in: i64 = @intCast(channels_in_usize);

        // IMPORTANT: src layout must be CHW flattened (C*36) matching training.
        // If your vector_board stores HWC per-square, you need to reorder here.
        // Your current pipeline wrote features exactly as vector.data, so keep consistent.

        const value = self.runner.run(
            channels_in,
            src,
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
        // NOTE: tree_search.expand() generates moves in the same order as priors_out.
        // priors_out.len == legal move count.
        //
        // For each move:
        //  Place: pos * type
        //  Slide: from * dir * pickup * slide_len(popcount)
        for (priors_out, 0..) |*p, i| {
            // tree_search passes priors_out pointing at node.priors, but doesn't pass moves.
            // So this eval() must be called from expand() after node.moves is set.
            // That’s already the case: node.moves is copied before eval_fn call.
            // We'll rely on a convention: expand() sets node.moves and then calls eval_fn.
            //
            // To access moves here, you’d need them passed in. Since EvalFn signature
            // doesn’t include moves, you have two options:
            //   A) Change EvalFn signature to include moves (best)
            //   B) Compute priors in expand() itself after calling eval_fn that outputs heads
            //
            // Because your EvalFn signature is fixed right now, the best minimal change is:
            //   - keep EvalFn for value only OR for raw head logits
            //   - compute priors in expand() where node.moves is in scope.
            //
            // So: we set dummy here and do the real mapping in expand().
            _ = i;
            p.* = 1.0;
        }

        return value;
    }
};

