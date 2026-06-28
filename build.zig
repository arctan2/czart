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

    const resources = b.createModule(.{
        .root_source_file = b.path("src/resources.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "raylib", .module = raylib },
        },
    });

    const layout = b.createModule(.{
        .root_source_file = b.path("src/layout.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "raylib", .module = raylib },
            .{ .name = "resources", .module = resources },
        },
    });

    const region = b.createModule(.{
        .root_source_file = b.path("src/region.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "layout", .module = layout },
            .{ .name = "raylib", .module = raylib },
            .{ .name = "resources", .module = resources },
        },
    });

    const widgets = b.createModule(.{
        .root_source_file = b.path("src/widgets/widgets.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "layout", .module = layout },
            .{ .name = "raylib", .module = raylib },
            .{ .name = "raygui", .module = raygui },
            .{ .name = "resources", .module = resources },
            .{ .name = "region", .module = region },
        },
    });

    const charts = b.createModule(.{
        .root_source_file = b.path("src/charts/charts.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "layout", .module = layout },
            .{ .name = "raylib", .module = raylib },
            .{ .name = "resources", .module = resources },
        },
    });

    const indicators = b.createModule(.{
        .root_source_file = b.path("src/indicators/indicators.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = common },
            .{ .name = "layout", .module = layout },
            .{ .name = "charts", .module = charts },
            .{ .name = "raylib", .module = raylib },
            .{ .name = "resources", .module = resources },
            .{ .name = "widgets", .module = widgets },
            .{ .name = "raygui", .module = raygui },
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
                .{ .name = "resources", .module = resources },
                .{ .name = "layout", .module = layout },
                .{ .name = "indicators", .module = indicators },
                .{ .name = "raylib", .module = raylib },
                .{ .name = "region", .module = region },
                .{ .name = "raygui", .module = raygui },
                .{ .name = "widgets", .module = widgets },
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
