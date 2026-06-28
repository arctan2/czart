const std = @import("std");
const rl = @import("raylib");
const Region = @import("region");
const Resources = @import("resources");
const charts = @import("charts");
const RootRegion = @import("regions/root_region.zig");

const Self = @This();
var SCREEN_RECT: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
var EVENT_CTX: Region.EventCtx = .{};

resources: Resources,
root: *RootRegion,
event_ctx: Region.EventCtx = .{},

pub fn init(allocator: std.mem.Allocator, screen_rect: rl.Rectangle, candles: []charts.CandleChart.Candle) !Self {
    SCREEN_RECT = screen_rect;

    return .{
        .resources = try .init(),
        .root = try .init(allocator, &SCREEN_RECT, candles)
    };
}

pub fn handleEvents(self: *Self, allocator: std.mem.Allocator) !void {
    const mouse = rl.getMousePosition();
    const wheel = rl.getMouseWheelMoveV();

    self.event_ctx.wheel_d = .{
        .x = wheel.x * self.event_ctx.zoom_sensitivity,
        .y = wheel.y * self.event_ctx.zoom_sensitivity
    };

    if(rl.isWindowResized()) {
        SCREEN_RECT.height = @as(f32, @floatFromInt(rl.getScreenHeight())) - (SCREEN_RECT.y * 2);
        SCREEN_RECT.width = @as(f32, @floatFromInt(rl.getScreenWidth())) - (SCREEN_RECT.x * 2);
    }

    _ = try self.root.region.handleEvents(allocator, &self.event_ctx);

    if (rl.isMouseButtonDown(.left)) {
        if (self.event_ctx.drag_start_mouse) |start| {
            const dx = mouse.x - start.x;
            const dy = mouse.y - start.y;
            self.event_ctx.mouse_d = .{ .x = dx, .y = dy };
        } else {
            self.event_ctx.drag_start_mouse = mouse;
        }
    }

    if (rl.isMouseButtonReleased(.left)) {
        self.event_ctx.drag_start_mouse = null;
        self.event_ctx.mouse_d = null;
    }
}

pub fn draw(self: *Self, allocator: std.mem.Allocator) !void {
    try self.root.region.draw(allocator, &self.event_ctx, &self.resources);
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.root.region.destroy(allocator);
}

