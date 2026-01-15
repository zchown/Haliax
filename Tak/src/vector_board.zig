const std = @import("std");
const brd = @import("board");
const tracy = @import("tracy");

const my_top_layer_offset: usize = 0;
const opp_top_layer_offset: usize = 3 * brd.board_size * brd.board_size;

const my_below_layer_offset: usize = 6 * brd.board_size * brd.board_size;
const opp_below_layer_offset: usize = 12 * brd.board_size * brd.board_size;

const my_reserve_layer_offset: usize = 18 * brd.board_size * brd.board_size;
const opp_reserve_layer_offset: usize = 20 * brd.board_size * brd.board_size;

const stack_len_offset: usize = 22 * brd.board_size * brd.board_size;
const my_covered_flats_offset: usize = 23 * brd.board_size * brd.board_size;
const their_covered_flats_offset: usize = 24 * brd.board_size * brd.board_size;

const flat_differential_offset: usize = 25 * brd.board_size * brd.board_size;

const total_channels: usize = 26;
const total_inputs: usize = brd.board_size * brd.board_size * total_channels;

pub const BoardState = struct {
    perspective: brd.Color, // Perspective of the player to move
                            // Computed based on indicatedplayers perspective
                            // 3 layers per color for top: flat, standing, capstone
                            // then 2 layers for 6 below stones: mine, opponent
                            // then 2 layers per color for stone and capstone reserve ratios
    data: [total_inputs]f32,

    pub fn init(perspective: brd.Color) BoardState {
        return BoardState{
            .perspective = perspective,
            .data = [_]f32{0} ** (total_inputs),
        };
    }

    pub fn clear(self: *BoardState) void {
        self.data = [_]f32{0} ** (total_inputs);
    }

    inline fn idx(chan: usize, pos: brd.Position) usize {
        return chan * brd.num_squares + @as(usize, @intCast(pos));
    }

    pub fn recompute(self: *BoardState, board: *brd.Board) void {
        self.clear();

        for (0..brd.num_squares) |pos| {
            self.recomputeSquare(board, @as(brd.Position, pos));
        }

        self.recomputeReserves(board);
    }

    pub fn recomputeSquare(self: *BoardState, board: *const brd.Board, pos: brd.Position,
    ) void {
        const square = board.squares[pos];

        // zero layers
        self.data[my_top_layer_offset + pos] = 0;
        self.data[my_top_layer_offset + pos + 1] = 0;
        self.data[my_top_layer_offset + pos + 2] = 0;
        self.data[opp_top_layer_offset + pos] = 0;
        self.data[opp_top_layer_offset + pos + 1] = 0;
        self.data[opp_top_layer_offset + pos + 2] = 0;
        for (0..6) |i| {
            self.data[my_below_layer_offset + pos + i * brd.num_squares] = 0;
            self.data[opp_below_layer_offset + pos + i * brd.num_squares] = 0;
        }

        if (square.top()) |top_piece| {
            const is_my_piece = top_piece.color == self.perspective;
            const top_layer_offset = if (is_my_piece) my_top_layer_offset else opp_top_layer_offset;

            switch (top_piece.stone_type) {
                .Flat => {
                    self.data[top_layer_offset + pos] = 1;
                },
                .Standing => {
                    self.data[top_layer_offset + pos + brd.num_squares] = 1;
                },
                .Capstone => {
                    self.data[top_layer_offset + pos + 2 * brd.num_squares] = 1;
                },
            }
        }

        if (square.len < 2) {
            return;
        }

        var my_below_piece_count: f32 = 0;
        var opp_below_piece_count: f32 = 0;

        var min_stack_index: usize = 0;
        if (square.len >= 7) {
            min_stack_index = square.len - 7;
        }
        for (0.. square.len - 2) |i| {
            const piece = square.stack[i].?;
            const is_my_piece = piece.color == self.perspective;
            if (is_my_piece) {
                my_below_piece_count += 1;
            } else {
                opp_below_piece_count += 1;
            }
            if (i < min_stack_index) continue;
            const below_layer_offset = if (is_my_piece) my_below_layer_offset else opp_below_layer_offset;
            self.data[below_layer_offset + pos + (i * brd.num_squares)] += 1;
        }
        self.data[stack_len_offset + pos] = @as(f32, @floatFromInt(square.len));
        self.data[my_covered_flats_offset + pos] = my_below_piece_count;
        self.data[their_covered_flats_offset + pos] = opp_below_piece_count;
    }

    pub fn recomputeReserves(self: *BoardState, board: *const brd.Board) void {
        var my_flat_count: usize = 0;
        var my_cap_count: usize = 0;
        var opp_flat_count: usize = 0;
        var opp_cap_count: usize = 0;
        if (self.perspective == .White) {
            my_flat_count = board.white_stones_remaining;
            my_cap_count = board.white_capstones_remaining;
            opp_flat_count = board.black_stones_remaining;
            opp_cap_count = board.black_capstones_remaining;
        } else {
            my_flat_count = board.black_stones_remaining;
            my_cap_count = board.black_capstones_remaining;
            opp_flat_count = board.white_stones_remaining;
            opp_cap_count = board.white_capstones_remaining;
        } 
        const my_flat_ratio = @as(f32, @floatFromInt(my_flat_count)) / @as(f32, @floatFromInt(brd.stone_count));
        const my_cap_ratio = @as(f32, @floatFromInt(my_cap_count)) / @as(f32, @floatFromInt(brd.capstone_count));
        const opp_flat_ratio = @as(f32, @floatFromInt(opp_flat_count)) / @as(f32, @floatFromInt(brd.stone_count));
        const opp_cap_ratio = @as(f32, @floatFromInt(opp_cap_count)) / @as(f32, @floatFromInt(brd.capstone_count));

        for (0..brd.num_squares) |pos| {
            self.data[my_reserve_layer_offset + pos] = my_flat_ratio;
            self.data[my_reserve_layer_offset + pos + brd.num_squares] = my_cap_ratio;

            self.data[opp_reserve_layer_offset + pos] = opp_flat_ratio;
            self.data[opp_reserve_layer_offset + pos + brd.num_squares] = opp_cap_ratio;
        }
    }

    pub fn placeMoveUpdate(self: *BoardState, pos: brd.Position, piece: brd.Piece) void {
        const is_my_piece = piece.color == self.perspective;
        const top_layer_offset = if (is_my_piece) my_top_layer_offset else opp_top_layer_offset;

        // Set new top layer
        switch (piece.stone_type) {
            .Flat => {
                self.data[top_layer_offset + pos] = 1;
            },
            .Standing => {
                self.data[top_layer_offset + pos + brd.num_squares] = 1;
            },
            .Capstone => {
                self.data[top_layer_offset + pos + 2 * brd.num_squares] = 1;
            },
        }

    }

    pub fn placeMoveUndo(self: *BoardState, pos: brd.Position) void {
        self.data[my_top_layer_offset + pos] = 0;
        self.data[my_top_layer_offset + pos + 1] = 0;
        self.data[my_top_layer_offset + pos + 2] = 0;
        self.data[opp_top_layer_offset + pos] = 0;
        self.data[opp_top_layer_offset + pos + 1] = 0;
        self.data[opp_top_layer_offset + pos + 2] = 0;
    }

    pub fn recomputeFlatDiff(self: *BoardState, board: *brd.Board) void {
        var my_flat_count: f32 = 0;
        var opp_flat_count: f32 = 0;

        const white_flats: brd.Bitboard = (board.white_control & ~board.standing_stones) & ~board.capstones;
        const black_flats: brd.Bitboard = (board.black_control & ~board.standing_stones) & ~board.capstones;

        if (self.perspective == .White) {
            my_flat_count = @as(f32, @floatFromInt(brd.countBits(white_flats)));
            opp_flat_count = @as(f32, @floatFromInt(brd.countBits(black_flats)));
            opp_flat_count += brd.komi;
        } else {
            my_flat_count = @as(f32, @floatFromInt(brd.countBits(black_flats)));
            opp_flat_count = @as(f32, @floatFromInt(brd.countBits(white_flats)));
            my_flat_count += brd.komi;
        }
        const flat_diff = my_flat_count - opp_flat_count;
        for (0..brd.num_squares) |pos| {
            self.data[flat_differential_offset + pos] = flat_diff;
        }
    }
};
