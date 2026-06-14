const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const common = b.createModule(.{
        .root_source_file = b.path("src/common.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });

    const layout = b.createModule(.{
        .root_source_file = b.path("src/layout.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "raylib", .module = raylib },
        },
    });

    const events = b.createModule(.{
        .root_source_file = b.path("src/events.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "layout", .module = layout },
            .{ .name = "raylib", .module = raylib },
        },
    });

    const charts = b.createModule(.{
        .root_source_file = b.path("src/charts/charts.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "layout", .module = layout },
            .{ .name = "events", .module = events },
            .{ .name = "raylib", .module = raylib },
        },
    });

    const exe = b.addExecutable(.{
        .name = "chart",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "charts", .module = charts },
                .{ .name = "common", .module = common },
                .{ .name = "layout", .module = layout },
                .{ .name = "events", .module = events },
                .{ .name = "raylib", .module = raylib },
                .{ .name = "raygui", .module = raygui },
            },
        }),
    });

    exe.root_module.linkLibrary(raylib_artifact);
    
    const csvzero = b.dependency("csvzero", .{});
    exe.root_module.addImport("csvzero", csvzero.module("csvzero"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    const docs_install = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate project and dependency documentation");
    docs_step.dependOn(&docs_install.step);

    run_cmd.step.dependOn(b.getInstallStep());
}
