const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const board_module = b.createModule(.{
        .root_source_file = b.path("Tak/src/board.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zobrist_module = b.createModule(.{
        .root_source_file = b.path("Tak/src/zobrist.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sympathy_module = b.createModule(.{
        .root_source_file = b.path("Tak/src/sympathy.zig"),
        .target = target,
        .optimize = optimize,
    });

    const moves_module = b.createModule(.{
        .root_source_file = b.path("Tak/src/moves.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ptn_module = b.createModule(.{
        .root_source_file = b.path("Tak/src/ptn.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tps_module = b.createModule(.{
        .root_source_file = b.path("Tak/src/tps.zig"),
        .target = target,
        .optimize = optimize,
    });

    board_module.addImport("zobrist", zobrist_module);

    zobrist_module.addImport("board", board_module);

    sympathy_module.addImport("board", board_module);

    moves_module.addImport("board", board_module);
    moves_module.addImport("sympathy", sympathy_module);
    moves_module.addImport("zobrist", zobrist_module);

    ptn_module.addImport("board", board_module);

    tps_module.addImport("board", board_module);

    const exe = b.addExecutable(.{
        .name = "Haliax",
        .root_module = b.createModule(.{
            .root_source_file = b.path("Tak/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("board", board_module);
    exe.root_module.addImport("moves", moves_module);
    exe.root_module.addImport("ptn", ptn_module);
    exe.root_module.addImport("tps", tps_module);
    exe.root_module.addImport("zobrist", zobrist_module);
    exe.root_module.addImport("sympathy", sympathy_module);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_step = b.step("test", "Run all unit tests");

    const test_files = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "board", .path = "Tak/test/board_test.zig" },
        .{ .name = "moves", .path = "Tak/test/moves_test.zig" },
        .{ .name = "ptn", .path = "Tak/test/ptn_test.zig" },
        .{ .name = "tps", .path = "Tak/test/tps_test.zig" },
        .{ .name = "zobrist", .path = "Tak/test/zobrist_test.zig" },
        .{ .name = "sympathy", .path = "Tak/test/sympathy_test.zig" },
    };

    for (test_files) |test_info| {
        const test_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_info.path),
                .target = target,
                .optimize = optimize,
            }),
        });

        test_exe.root_module.addImport("board", board_module);
        test_exe.root_module.addImport("moves", moves_module);
        test_exe.root_module.addImport("ptn", ptn_module);
        test_exe.root_module.addImport("tps", tps_module);
        test_exe.root_module.addImport("zobrist", zobrist_module);
        test_exe.root_module.addImport("sympathy", sympathy_module);

        const run_test = b.addRunArtifact(test_exe);

        test_step.dependOn(&run_test.step);

        const test_name = b.fmt("test-{s}", .{test_info.name});
        const test_desc = b.fmt("Run {s} tests", .{test_info.name});
        const individual_test_step = b.step(test_name, test_desc);
        individual_test_step.dependOn(&run_test.step);
    }
}
