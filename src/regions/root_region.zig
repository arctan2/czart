const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const indicators = @import("indicators");
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
layout: Layout,
candle_chart: charts.CandleChart,
sma: indicators.SMA,
ema: indicators.EMA,

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle, candles: []charts.CandleChart.Candle) !Self {
    const candle_chart = charts.CandleChart{ .candles = candles };
    return .{
        .layout = .init(screen_rect, candle_chart.calcMinMax()),
        .candle_chart = candle_chart,
        .sma = try .init(allocator, candles, 50),
        .ema = try .init(allocator, candles, 50),
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.sma.deinit(allocator);
    self.ema.deinit(allocator);
}

fn drawXAxis(self: *Self, allocator: std.mem.Allocator, resources: *Resources) void {
    const axis_y = self.layout.screen_rect.height - (self.layout.top / 2);
    const label_y = axis_y + 8.0;

    const stride = self.layout.tickStride();
    const first_tick = @ceil(self.layout.view_x.min / stride) * stride;
    const shows_time = self.timeframe.showsTime();

    rl.drawRectangle(
        @intFromFloat(self.layout.left),
        @intFromFloat(axis_y),
        @intFromFloat(self.layout.width + Layout.Y_AXIS_WIDTH),
        @intFromFloat(Layout.X_AXIS_HEIGHT),
        Resources.AXIS_BG,
    );

    var index: f32 = first_tick;
    while (index <= self.layout.view_x.max) : (index += stride) {
        const sx = self.layout.indexToScreenX(index);
        if (sx < self.layout.left or sx > self.layout.right()) continue;

        rl.drawLineEx(
            .{ .x = sx, .y = self.layout.top },
            .{ .x = sx, .y = axis_y },
            1.0,
            Resources.GRID_COLOR
        );

        rl.drawLineEx(
            .{ .x = sx, .y = axis_y },
            .{ .x = sx, .y = axis_y + 5.0 },
            1.0,
            .{ .r = 120, .g = 120, .b = 120, .a = 255 },
        );

        const ts = self.candle_chart.indexToTs(index);
        const epoch_seconds = @divFloor(ts, 1000);

        const text = (
            if (shows_time)
                DateFormatter.toTextualTime(allocator, epoch_seconds)
            else
                DateFormatter.toTextual(allocator, epoch_seconds)
        ) catch continue;
        defer allocator.free(text);

        const text_size = rl.measureTextEx(resources.font, text, Layout.PRICE_FONT_SIZE, 1);
        const label_x = sx - text_size.x / 2.0;
        rl.drawTextEx(resources.font, text, .{ .x = label_x, .y = label_y }, Layout.PRICE_FONT_SIZE, 1, .white);
    }
}

fn draw(self: *Self, allocator: std.mem.Allocator, resources: *Resources) void {
    rl.drawRectangleV(
        .{ .x = self.layout.left, .y = self.layout.top },
        .{ .x = self.layout.width, .y = self.layout.height },
        Resources.CHART_BG
    );

    self.layout.drawYAxis(resources);
    self.drawXAxis(allocator, resources);
    self.candle_chart.drawCandles(&self.layout);
    self.sma.draw(&self.layout, self.candle_chart.candles);
    self.ema.draw(&self.layout, self.candle_chart.candles);
    self.candle_chart.drawCrosshair(allocator, &self.layout, resources);
}

fn scroll(self: *Self, ctx: *Region.EventCtx, change_time_axis: bool) void {
    const mid_x = self.layout.right() / 2;
    const cursor_index = self.layout.screenXToIndex(mid_x);
    if (change_time_axis) {
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;
        const new_min = cursor_index + (self.layout.view_x.min - cursor_index) * factor;
        const new_max = cursor_index + (self.layout.view_x.max - cursor_index) * factor;
        const diff = new_max - new_min;

        const max_points_in_view: f32 = @floatFromInt(self.candle_chart.candles.len * 2 + 64);
        if (diff > 4 and diff < max_points_in_view) {
            self.layout.view_x.min = new_min;
            self.layout.view_x.max = new_max;
        }
    } else {
        const cursor_price = (self.layout.view_y.max - self.layout.view_y.min) / 2 + self.layout.view_y.min;
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;

        const new_min = cursor_price + (self.layout.view_y.min - cursor_price) * factor;
        const new_max = cursor_price + (self.layout.view_y.max - cursor_price) * factor;
        const diff = new_max - new_min;
        if (diff > 0.001 and diff < 3_000_000_000) {
            self.layout.view_y.min = new_min;
            self.layout.view_y.max = new_max;
        }
    }
}

fn handleEvents(self: *Self, ctx: *Region.EventCtx) void {
    if (ctx.isWheelScroll()) {
        if (ctx.isHorizontalScroll()) {
            const scroll_x_multiplier = self.layout.view_x.range() / 10;
            self.layout.view_x.min -= ctx.wheel_d.x * scroll_x_multiplier;
            self.layout.view_x.max -= ctx.wheel_d.x * scroll_x_multiplier;
        } else {
            self.scroll(ctx, rl.isKeyDown(.left_shift) or rl.isKeyDown(.left_control));
        }
    }
    
    if (ctx.mouse_d) |mouse_d| {
        const index_per_pixel = ctx.drag_start_view_x.range() / self.layout.width;
        self.layout.view_x.min = ctx.drag_start_view_x.min - mouse_d.x * index_per_pixel;
        self.layout.view_x.max = ctx.drag_start_view_x.max - mouse_d.x * index_per_pixel;

        const price_per_pixel = ctx.drag_start_view_y.range() / self.layout.height;
        self.layout.view_y.min = ctx.drag_start_view_y.min + mouse_d.y * price_per_pixel;
        self.layout.view_y.max = ctx.drag_start_view_y.max + mouse_d.y * price_per_pixel;
    } else if(rl.isMouseButtonDown(.left)) {
        ctx.drag_start_view_x = self.layout.view_x;
        ctx.drag_start_view_y = self.layout.view_y;
    }
}

fn handleEventsRegion(ptr: *anyopaque, _: std.mem.Allocator, ctx: *Region.EventCtx) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));

    if(rl.isWindowResized()) {
        self.layout.height = self.layout.screen_rect.height - Layout.X_AXIS_HEIGHT;
        self.layout.width = self.layout.screen_rect.width - Layout.Y_AXIS_WIDTH;
    }

    self.handleEvents(ctx);

    if (rl.isKeyPressed(.r)) {
        var mm = self.candle_chart.calcMinMax();
        mm.y.pad(Layout.CHART_PAD);
        mm.x.pad(Layout.CHART_PAD);
        self.layout.view_y = mm.y;
        self.layout.view_x = mm.x;
    }
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, resources: *Resources) void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.draw(allocator, resources);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.deinit(allocator);
}

pub fn region(self: *Self) Region {
    return .{
        .ptr = @ptrCast(self),
        .drawFn = drawRegion,
        .handleEventsFn = handleEventsRegion,
        .destroyFn = deinitRegion
    };
}

