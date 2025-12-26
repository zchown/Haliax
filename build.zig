const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tracy = b.option([]const u8, "tracy", "Enable Tracy integration. Supply path to Tracy source");
    const tracy_callstack = b.option(bool, "tracy-callstack", "Include callstack information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy != null);
    const tracy_allocation = b.option(bool, "tracy-allocation", "Include allocation information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy != null);
    const tracy_callstack_depth: u32 = b.option(u32, "tracy-callstack-depth", "Declare callstack depth for Tracy data. Does nothing if -Dtracy-callstack is not provided") orelse 10;

    const tracy_module = b.createModule(.{
        .root_source_file = b.path("Tracy/tracy.zig"),
        .target = target,
        .optimize = optimize,
    });

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
    board_module.addImport("tracy", tracy_module);

    zobrist_module.addImport("board", board_module);
    zobrist_module.addImport("tracy", tracy_module);

    sympathy_module.addImport("board", board_module);

    moves_module.addImport("board", board_module);
    moves_module.addImport("sympathy", sympathy_module);
    moves_module.addImport("zobrist", zobrist_module);
    moves_module.addImport("tracy", tracy_module);

    ptn_module.addImport("board", board_module);

    tps_module.addImport("board", board_module);

    const exe = b.addExecutable(.{
        .name = "Haliax",
        .root_module = b.createModule(.{
            .root_source_file = b.path("Tak/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = true,
    });

    exe.root_module.addImport("board", board_module);
    exe.root_module.addImport("moves", moves_module);
    exe.root_module.addImport("ptn", ptn_module);
    exe.root_module.addImport("tps", tps_module);
    exe.root_module.addImport("zobrist", zobrist_module);
    exe.root_module.addImport("sympathy", sympathy_module);
    exe.root_module.addImport("tracy", tracy_module);

    b.installArtifact(exe);

    const gen = b.addExecutable(.{
        .name = "magics",
        .root_module = b.createModule(.{
            .root_source_file = b.path("Tak/tools/gen_magic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gen.root_module.addImport("board", board_module);
    b.installArtifact(gen);
    const magics_step = b.step("magics", "Build the magic-table generator");
    magics_step.dependOn(&gen.step);
    const run_gen = b.addRunArtifact(gen);
    const gen_step = b.step("gen-magics", "Run generator and print Zig tables to stdout");
    gen_step.dependOn(&run_gen.step);

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
    tracy_module.addOptions("build_options", exe_options);

    exe_options.addOption(bool, "enable_tracy", tracy != null);
    exe_options.addOption(bool, "enable_tracy_callstack", tracy_callstack);
    exe_options.addOption(bool, "enable_tracy_allocation", tracy_allocation);
    exe_options.addOption(u32, "tracy_callstack_depth", tracy_callstack_depth);

    if (tracy) |tracy_path| {
        const client_cpp = b.pathJoin(&[_][]const u8{ tracy_path, "public", "TracyClient.cpp" });
        const tracy_c_flags: []const []const u8 = &.{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        exe.root_module.addIncludePath(.{ .cwd_relative = tracy_path });
        exe.root_module.addCSourceFile(.{ .file = .{ .cwd_relative = client_cpp }, .flags = tracy_c_flags });
        exe.root_module.linkSystemLibrary("c++", .{ .use_pkg_config = .no });
        exe.root_module.link_libc = true;
    }

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
        test_exe.root_module.addImport("tracy", tracy_module);

        const test_options = b.addOptions();
        test_exe.root_module.addOptions("build_options", test_options);

        test_options.addOption(bool, "enable_tracy", tracy != null);
        test_options.addOption(bool, "enable_tracy_callstack", tracy_callstack);
        test_options.addOption(bool, "enable_tracy_allocation", tracy_allocation);
        test_options.addOption(u32, "tracy_callstack_depth", tracy_callstack_depth);

        if (tracy) |tracy_path| {
            const client_cpp = b.pathJoin(&[_][]const u8{ tracy_path, "public", "TracyClient.cpp" });
            const tracy_c_flags: []const []const u8 = &.{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

            test_exe.root_module.addIncludePath(.{ .cwd_relative = tracy_path });
            test_exe.root_module.addCSourceFile(.{ .file = .{ .cwd_relative = client_cpp }, .flags = tracy_c_flags });
            test_exe.root_module.linkSystemLibrary("c++", .{ .use_pkg_config = .no });
            test_exe.root_module.link_libc = true;
        }

        const run_test = b.addRunArtifact(test_exe);

        test_step.dependOn(&run_test.step);

        const test_name = b.fmt("test-{s}", .{test_info.name});
        const test_desc = b.fmt("Run {s} tests", .{test_info.name});
        const individual_test_step = b.step(test_name, test_desc);
        individual_test_step.dependOn(&run_test.step);

    }
}

