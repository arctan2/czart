const rl = @import("raylib");
const std = @import("std");
const Layout = @import("layout");

const Self = @This();

pub fn draw(
    layout: *const Layout,
    points: []rl.Vector2,
    color: rl.Color
) void {
    rl.beginScissorMode(
        @intFromFloat(layout.left),
        @intFromFloat(layout.top),
        @intFromFloat(layout.width),
        @intFromFloat(layout.scaledHeight()),
    );
    defer rl.endScissorMode();

    rl.drawSplineLinear(points, 1, color);
}

