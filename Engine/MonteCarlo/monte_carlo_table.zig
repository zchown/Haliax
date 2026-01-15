const std = @import("std");
const zob = @import("zobrist");

pub const NodeState = enum(u8) { Unknown, Win, Loss, Draw };
