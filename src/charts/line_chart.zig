const rl = @import("raylib");
const std = @import("std");
const Layout = @import("layout");

const Self = @This();

pub fn draw(
    layout: *const Layout,
    points: []rl.Vector2,
    color: rl.Color
) void {
    layout.beginScissorMode();
    defer rl.endScissorMode();

    rl.drawSplineLinear(points, 1, color);
}

