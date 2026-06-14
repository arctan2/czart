const rl = @import("raylib");
const std = @import("std");
const common = @import("common");
const Timeframe = common.Timeframe;
const DateFormatter = common.DateFormatter;
const Layout = @import("layout").Layout;

pub const Self = @This();

points: []rl.Vector2,

pub fn draw(self: *Self, layout: *const Layout) void {
    rl.beginScissorMode(
        @intFromFloat(layout.chartLeft()),
        @intFromFloat(layout.chartTop()),
        @intFromFloat(layout.chart_screen_rect.width),
        @intFromFloat(layout.chart_screen_rect.height),
    );
    defer rl.endScissorMode();

}

