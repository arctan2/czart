const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const Region = @import("region");
const EventCtx = Region.EventCtx;

const Self = @This();

layout: Layout,
candle_chart: *charts.CandleChart,
tools: std.ArrayList(*Region),

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle, candle_chart: *charts.CandleChart) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .candle_chart = candle_chart,
        .tools = try .initCapacity(allocator, 0),
        .layout = .empty(screen_rect)
    };

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.tools.deinit(allocator);
    allocator.destroy(self);
}

pub fn draw(_: *Self, _: std.mem.Allocator, _: *EventCtx, _: *Resources) !void {
}

pub fn handleEvents(self: *Self, _: std.mem.Allocator, _: *EventCtx) !void {
    if(rl.isWindowResized()) {
        self.layout.height = self.layout.screen_rect.height - charts.CandleChart.X_AXIS_HEIGHT;
        self.layout.width = self.layout.screen_rect.width - charts.CandleChart.Y_AXIS_WIDTH;
    }
}

