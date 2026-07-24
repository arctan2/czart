const std = @import("std");
const rl = @import("raylib");
const Region = @import("region");
const Resources = @import("resources");
const charts = @import("charts");
const PaneLayer = @import("layers/pane_layer.zig");
const DialogLayer = @import("layers/dialog_layer.zig");
const ToolsLayer = @import("layers/tools_layer.zig");
const IndicatorPickerLayer = @import("layers/indicator_picker_layer.zig");
const ActiveIndicators = @import("active_indicators.zig");

const Self = @This();
var SCREEN_RECT: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
var EVENT_CTX: Region.EventCtx = .{};

resources: Resources,
pane_layer: *PaneLayer,
dialog_layer: *DialogLayer,
tools_layer: *ToolsLayer,
indicator_picker_layer: *IndicatorPickerLayer,
event_ctx: Region.EventCtx = .{},

pub fn init(allocator: std.mem.Allocator, screen_rect: rl.Rectangle, candles: []charts.CandleChart.Candle) !Self {
    SCREEN_RECT = screen_rect;

    const pane_layer: *PaneLayer = try .init(allocator, &SCREEN_RECT, candles);
    const indicator_picker_layer: *IndicatorPickerLayer = try .init(
        allocator, &SCREEN_RECT, &pane_layer.region, pane_layer.candle_chart, pane_layer.active_indicators
    );
    const dialog_layer: *DialogLayer = try .init(allocator, &SCREEN_RECT, pane_layer.candle_chart);
    const tools_layer: *ToolsLayer = try .init(allocator, &SCREEN_RECT, pane_layer.candle_chart);

    return .{
        .resources = try .init(),
        .pane_layer = pane_layer,
        .indicator_picker_layer = indicator_picker_layer,
        .dialog_layer = dialog_layer,
        .tools_layer = tools_layer,
    };
}

pub fn handleEvents(self: *Self, allocator: std.mem.Allocator) !void {
    const mouse = rl.getMousePosition();
    const wheel = rl.getMouseWheelMoveV();
    self.event_ctx.state = .{};

    if(rl.isMouseButtonPressed(.left)) {
        self.event_ctx.focused = null;
    }

    self.event_ctx.wheel_d = .{
        .x = wheel.x * self.event_ctx.zoom_sensitivity,
        .y = wheel.y * self.event_ctx.zoom_sensitivity
    };

    if(rl.isWindowResized()) {
        SCREEN_RECT.height = @as(f32, @floatFromInt(rl.getScreenHeight())) - (SCREEN_RECT.y * 2);
        SCREEN_RECT.width = @as(f32, @floatFromInt(rl.getScreenWidth())) - (SCREEN_RECT.x * 2);
    }

    if(rl.isWindowResized()) {
        self.indicator_picker_layer.handleResize();
        self.tools_layer.handleResize();
        self.pane_layer.handleResize();
    }

    if(!try self.indicator_picker_layer.handleEvents(allocator, &self.event_ctx)) {
        if(!try self.tools_layer.handleEvents(allocator, &self.event_ctx)) {
            try self.pane_layer.region.handleEvents(allocator, &self.event_ctx);
        }
    }

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
        self.event_ctx.captured = null;
    }
}

pub fn draw(self: *Self, allocator: std.mem.Allocator) !void {
    try self.pane_layer.region.draw(allocator, &self.event_ctx, &self.resources);
    try self.tools_layer.draw(allocator, &self.event_ctx, &self.resources);
    try self.indicator_picker_layer.draw(allocator, &self.event_ctx, &self.resources);
    try self.dialog_layer.draw(allocator, &self.event_ctx, &self.resources);
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.dialog_layer.deinit(allocator);
    self.tools_layer.deinit(allocator);
    self.indicator_picker_layer.deinit(allocator);
    self.pane_layer.region.destroy(allocator);
}

