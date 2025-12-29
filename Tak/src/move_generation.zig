const std = @import("std");
const brd = @import("board");
const sym = @import("sympathy");
const magic = @import("magics");
const tracy = @import("tracy");
const tracy_enable = tracy.build_options.enable_tracy;

pub const MoveGeneratorSettings = struct {
    place_first: bool,
    place_only: bool,
    slide_only: bool,
};

pub const MoveGenerator = struct {
    board: *brd.Board,
    state: GeneratorState,

    place_only: bool,
    slide_only: bool,
    place_first: bool,

    stones_remaining: usize,
    capstones_remaining: usize,
    controlled_squares: brd.Bitboard,

    const GeneratorState = struct {
        doing_place: bool,

        place_moves: [brd.num_squares * 3]brd.Move,
        place_move_count: usize,
        place_cur_index: usize,

        controlled_remaining: brd.Bitboard,
        current_pos: brd.Position,
        current_dir: brd.Direction,
        pos_active: bool,

        slide_can_crush: bool,
        slide_max_pickup: u8,

        pattern: ?*const sym.PatternList,
        pattern_index: u8,
    };

    pub fn init(board: *brd.Board, settings: MoveGeneratorSettings) MoveGenerator {
        var gen = MoveGenerator{
            .board = board,
            .state = .{
                .doing_place = settings.place_first,

                .place_moves = @splat(brd.Move{ .position = 0, .pattern = 0, .flag = 0 }),
                .place_move_count = 0,
                .place_cur_index = 0,
                .pos_active = false,

                .controlled_remaining = 0,
                .current_pos = 0,
                .current_dir = .North,

                .slide_can_crush = false,
                .slide_max_pickup = 0,

                .pattern = null,
                .pattern_index = 0,
            },

            .place_only = settings.place_only,
            .slide_only = settings.slide_only,
            .place_first = settings.place_first,

            .stones_remaining = if (board.to_move == brd.Color.White)
                board.white_stones_remaining
            else
                board.black_stones_remaining,

            .capstones_remaining = if (board.to_move == brd.Color.White)
                board.white_capstones_remaining
            else
                board.black_capstones_remaining,

            .controlled_squares = if (board.to_move == brd.Color.White)
                board.white_control
            else
                board.black_control,
        };

        if (gen.board.half_move_count < 2) {
            gen.place_only = true;
        }

        if (!gen.slide_only) gen.generatePlaceMoves();

        if (!gen.place_only) {
            gen.state.controlled_remaining = gen.controlled_squares;
            gen.state.pattern = null;
            _ = gen.advanceSlideSource(); // prime
        }

        return gen;
    }

    pub fn initDefault(board: *brd.Board) MoveGenerator {
        return MoveGenerator.init(board, .{
            .place_first = true,
            .place_only = false,
            .slide_only = false,
        });
    }

    pub fn reset(self: *MoveGenerator, settings: MoveGeneratorSettings) void {
        self.place_only = settings.place_only;
        self.slide_only = settings.slide_only;
        self.place_first = settings.place_first;

        self.state.doing_place = settings.place_first;

        self.state.place_move_count = 0;
        self.state.place_cur_index = 0;

        self.state.controlled_remaining = self.controlled_squares;
        self.state.current_pos = 0;
        self.state.current_dir = .North;
        self.state.pattern = null;
        self.state.pattern_index = 0;

        if (!self.slide_only) self.generatePlaceMoves();
        if (!self.place_only) _ = self.advanceSlideSource();
    }

    pub fn next(self: *MoveGenerator) ?brd.Move {
        if (tracy_enable) {
            const tr = tracy.trace(@src());
            defer tr.end();
        }
        if (self.state.doing_place) {
            if (self.nextPlace()) |mv| return mv;

            if (self.place_only or !self.place_first) return null;

            self.state.doing_place = false;
            return self.nextSlide();
        } else {
            if (self.nextSlide()) |mv| return mv;

            if (self.slide_only or self.place_first) return null;

            self.state.doing_place = true;
            return self.nextPlace();
        }
    }

    fn nextPlace(self: *MoveGenerator) ?brd.Move {
        if (tracy_enable) {
            const tr = tracy.trace(@src());
            defer tr.end();
        }
        if (self.state.place_cur_index < self.state.place_move_count) {
            const mv = self.state.place_moves[self.state.place_cur_index];
            self.state.place_cur_index += 1;
            return mv;
        }
        return null;
    }

    fn nextSlide(self: *MoveGenerator) ?brd.Move {
        if (tracy_enable) {
            const tr = tracy.trace(@src());
            defer tr.end();
        }
        while (true) {
            if (self.state.pattern) |plist_ptr| {
                if (self.state.pattern_index < plist_ptr.len) {
                    const pat = plist_ptr.items[self.state.pattern_index];
                    self.state.pattern_index += 1;

                    return brd.Move{
                        .position = self.state.current_pos,
                        .pattern = pat,
                        .flag = @intFromEnum(self.state.current_dir),
                    };
                }
            }

            if (!self.advanceSlideSource()) return null;
        }
    }

    fn generatePlaceMoves(self: *MoveGenerator) void {
        if (tracy_enable) {
            const tr = tracy.trace(@src());
            defer tr.end();
        }
        self.state.place_move_count = 0;
        self.state.place_cur_index = 0;

        if (self.board.half_move_count < 2) {
            for (0..brd.num_squares) |pos_usize| {
                const pos: brd.Position = @intCast(pos_usize);
                if (!self.board.isSquareEmpty(pos)) continue;

                self.state.place_moves[self.state.place_move_count] = .{
                    .position = pos,
                    .pattern = 0,
                    .flag = @intFromEnum(brd.StoneType.Flat),
                };
                self.state.place_move_count += 1;
            }
            return;
        }

        for (0..brd.num_squares) |pos_usize| {
            const pos: brd.Position = @intCast(pos_usize);
            if (!self.board.isSquareEmpty(pos)) continue;

            if (self.stones_remaining > 0) {
                self.state.place_moves[self.state.place_move_count] = .{
                    .position = pos,
                    .pattern = 0,
                    .flag = @intFromEnum(brd.StoneType.Flat),
                };
                self.state.place_move_count += 1;

                self.state.place_moves[self.state.place_move_count] = .{
                    .position = pos,
                    .pattern = 0,
                    .flag = @intFromEnum(brd.StoneType.Standing),
                };
                self.state.place_move_count += 1;
            }

            if (self.capstones_remaining > 0) {
                self.state.place_moves[self.state.place_move_count] = .{
                    .position = pos,
                    .pattern = 0,
                    .flag = @intFromEnum(brd.StoneType.Capstone),
                };
                self.state.place_move_count += 1;
            }
        }
    }

    fn advanceSlideSource(self: *MoveGenerator) bool {
        while (true) {
            if (!self.state.pos_active) {
                if (!self.popNextControlled()) return false;
                self.state.current_dir = .North;
                self.cacheSlidePosData();
                self.state.pos_active = true;
            } else {
                if (self.state.current_dir == .West) {
                    if (!self.popNextControlled()) return false;
                    self.state.current_dir = .North;
                    self.cacheSlidePosData();
                    self.state.pos_active = true;
                } else {
                    self.state.current_dir =
                        @enumFromInt(@intFromEnum(self.state.current_dir) + 1);
                }
            }

            if (self.computePatternForCurrent()) return true;
        }
    }

    fn popNextControlled(self: *MoveGenerator) bool {
        var bb = self.state.controlled_remaining;
        if (bb == 0) return false;

        const idx: u6 = @intCast(@ctz(bb));
        self.state.current_pos = idx;
        bb &= (bb - 1);
        self.state.controlled_remaining = bb;
        return true;
    }

    fn cacheSlidePosData(self: *MoveGenerator) void {
        if (tracy_enable) {
            const tr = tracy.trace(@src());
            defer tr.end();
        }
        const pos = self.state.current_pos;
        const sq_len: usize = self.board.squares[pos].len;
        const max_pickup: usize = if (sq_len < brd.max_pickup) sq_len else brd.max_pickup;

        self.state.slide_max_pickup = @intCast(max_pickup);
        self.state.slide_can_crush = ((self.board.capstones & brd.getPositionBB(pos)) != 0);
    }

    fn computePatternForCurrent(self: *MoveGenerator) bool {
        if (tracy_enable) {
            const tr = tracy.trace(@src());
            defer tr.end();
        }
        self.state.pattern = null;
        self.state.pattern_index = 0;

        const pos = self.state.current_pos;
        const dir = self.state.current_dir;

        const max_pickup_u8 = self.state.slide_max_pickup;
        if (max_pickup_u8 == 0) return false;

        var max_steps: usize = magic.numSteps(self.board, pos, dir);

        const max_pickup: usize = @intCast(max_pickup_u8);
        if (max_steps > max_pickup) max_steps = max_pickup;

        var doing_crush = false;
        if (self.state.slide_can_crush and max_steps < brd.max_pickup) {
            const start_bb = brd.getPositionBB(pos);
            const end_pos_bb = brd.bbGetNthPositionFrom(start_bb, dir, @intCast(max_steps + 1));
            doing_crush = (self.board.standing_stones & end_pos_bb) != 0;
        }

        if (doing_crush) {
            self.state.pattern = &sym.patterns.combined_patterns[max_pickup - 1][max_steps];
        } else {
            if (max_steps == 0) return false;
            self.state.pattern = &sym.patterns.patterns[max_pickup - 1][max_steps - 1];
        }

        return true;
    }
};
