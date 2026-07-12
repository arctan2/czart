const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const common = @import("common");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const Timeframe = common.Timeframe;
const MinMax = common.MinMax;
const DateFormatter = common.DateFormatter;
const Region = @import("region");

const Self = @This();

timeframe: Timeframe = .m1,
layout: *Layout,
candle_chart: *charts.CandleChart,
region: Region,

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle, candles: []charts.CandleChart.Candle) !*Self {
    const self = try allocator.create(Self);
    var candle_chart = try allocator.create(charts.CandleChart);
    candle_chart.* = .init(screen_rect, candles);

    self.* = .{
        .layout = &candle_chart.layout,
        .candle_chart = candle_chart,
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .destroyFn = deinitRegion,
        }
    };

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.destroy(self.candle_chart);
    allocator.destroy(self);
}

fn draw(self: *Self, allocator: std.mem.Allocator, resources: *Resources) !void {
    rl.drawRectangleV(
        .{ .x = self.layout.left, .y = self.layout.top },
        .{ .x = self.layout.width, .y = self.layout.height },
        Resources.CHART_BG
    );

    self.candle_chart.drawYAxis(resources);
    try self.candle_chart.drawXAxis(allocator, resources);
    self.candle_chart.drawCandles();
    if(rl.checkCollisionPointRec(rl.getMousePosition(), self.candle_chart.layout.getRect())) {
        try self.candle_chart.drawCrosshair(allocator, self.layout, &self.candle_chart.view.y, resources);
    }
}

fn scroll(self: *Self, ctx: *Region.EventCtx, change_time_axis: bool) void {
    const mouse = rl.getMousePosition();

    if (change_time_axis) {
        const cursor_index = self.candle_chart.screenXToIndex(mouse.x);
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;
        const new_min = cursor_index + (self.candle_chart.view.x.min - cursor_index) * factor;
        const new_max = cursor_index + (self.candle_chart.view.x.max - cursor_index) * factor;
        const diff = new_max - new_min;

        const max_points_in_view: f32 = @floatFromInt(self.candle_chart.candles.len * 2 + 64);
        if (diff > 4 and diff < max_points_in_view) {
            self.candle_chart.view.x.min = new_min;
            self.candle_chart.view.x.max = new_max;
        }
    } else {
        const cursor_price = charts.CandleChart.screenToViewY(self.layout, &self.candle_chart.view.y, mouse.y);
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;

        const new_min = cursor_price + (self.candle_chart.view.y.min - cursor_price) * factor;
        const new_max = cursor_price + (self.candle_chart.view.y.max - cursor_price) * factor;
        const diff = new_max - new_min;
        if (diff > 0.001 and diff < 3_000_000_000) {
            self.candle_chart.view.y.min = new_min;
            self.candle_chart.view.y.max = new_max;
        }
    }
}

fn handleEvents(self: *Self, ctx: *Region.EventCtx) void {
    if (ctx.isWheelScroll()) {
        if (ctx.isHorizontalScroll()) {
            const scroll_x_multiplier = self.candle_chart.view.x.range() / 10;
            self.candle_chart.view.x.min -= ctx.wheel_d.x * scroll_x_multiplier;
            self.candle_chart.view.x.max -= ctx.wheel_d.x * scroll_x_multiplier;
        } else {
            self.scroll(ctx, rl.isKeyDown(.left_shift) or rl.isKeyDown(.left_control));
        }
    }

    const owns_mouse_down = ctx.tryOwnMouseDown(@ptrCast(self), self.candle_chart.layout.getRect());

    if (ctx.mouse_d) |mouse_d| {
        const index_per_pixel = ctx.drag_start_view_x.range() / self.layout.width;
        self.candle_chart.view.x.min = ctx.drag_start_view_x.min - mouse_d.x * index_per_pixel;
        self.candle_chart.view.x.max = ctx.drag_start_view_x.max - mouse_d.x * index_per_pixel;

        if(ctx.state.y_pan == 0 and owns_mouse_down) {
            const price_per_pixel = ctx.drag_start_view_y.range() / self.layout.height;
            self.candle_chart.view.y.min = ctx.drag_start_view_y.min + mouse_d.y * price_per_pixel;
            self.candle_chart.view.y.max = ctx.drag_start_view_y.max + mouse_d.y * price_per_pixel;
        }
    } else if(rl.isMouseButtonDown(.left)) {
        ctx.drag_start_view_x = self.candle_chart.view.x;

        if(ctx.state.mouse_left_down == 0 and owns_mouse_down) {
            ctx.drag_start_view_y = self.candle_chart.view.y;
        }
    }
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *Region.EventCtx) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));

    if(rl.isWindowResized()) {
        self.layout.height = self.layout.screen_rect.height - charts.CandleChart.X_AXIS_HEIGHT;
        self.layout.width = self.layout.screen_rect.width - charts.CandleChart.Y_AXIS_WIDTH;
    }

    if(self.region.child) |child| {
        try child.handleEvents(allocator, ctx);
        if(ctx.state.view_y_resize == 1) {
            return;
        }
    }

    self.handleEvents(ctx);

    if (rl.isKeyPressed(.r)) {
        var mm = charts.CandleChart.calcMinMax(self.candle_chart.candles);
        mm.y.pad(charts.CandleChart.CHART_PAD);
        mm.x.pad(charts.CandleChart.CHART_PAD);
        self.candle_chart.view.y = mm.y;
        self.candle_chart.view.x = mm.x;
    }
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, _: *Region.EventCtx, resources: *Resources) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try self.draw(allocator, resources);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.deinit(allocator);
}

