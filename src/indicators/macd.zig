const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");
const Resources = @import("resources");
const Region = @import("region");
const common = @import("common");
const EventCtx = Region.EventCtx;
const MinMax = common.MinMax;

const Self = @This();

macd_line: []rl.Vector2,
signal_line: []rl.Vector2,
layout: Layout,
region: Region,
candle_chart: *charts.CandleChart,
view_y: MinMax,

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle, candle_chart: *charts.CandleChart) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .macd_line = try allocator.alloc(rl.Vector2, (candle_chart.candles.len - 26) + 1),
        .signal_line = try allocator.alloc(rl.Vector2, (candle_chart.candles.len - 26) + 1),
        .layout = .empty(screen_rect),
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .destroyFn = deinitRegion
        },
        .candle_chart = candle_chart,
        .view_y = .{ .max = 2, .min = -2 }
    };

    self.candle_chart.layout.height_scale = 0.7;

    self.computeLayout();

    return self;
}

fn computeLayout(self: *Self) void {
    self.layout.height = self.candle_chart.layout.height * 0.3;
    self.layout.width = self.layout.screen_rect.width - charts.CandleChart.Y_AXIS_WIDTH;
    self.layout.left = self.candle_chart.layout.left;
    self.layout.top = self.candle_chart.layout.scaledBottom();
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.candle_chart.layout.height_scale = 1;
    allocator.free(self.macd_line);
    allocator.free(self.signal_line);
    allocator.destroy(self);
}

pub fn toScreenY(self: *const Self, p: f32) f32 {
    const t = (p - self.view_y.min) / self.view_y.range();
    return (self.layout.height * (1.0 - t)) + self.layout.top;
}

fn computeMACD(self: *const Self) void {
    if (self.candle_chart.candles.len < 26) return;

    var sum_12: f32 = 0;
    var sum_26: f32 = 0;

    for (self.candle_chart.candles[12..24]) |candle| sum_12 += candle.close;
    for (self.candle_chart.candles[0..26]) |candle| sum_26 += candle.close;

    var prev_ema_12 = sum_12 / 12.0;
    var prev_ema_26 = sum_26 / 26.0;

    const M12: f32 = 2.0 / 13.0;
    const M26: f32 = 2.0 / 27.0;

    for (12..26) |i| {
        const candle = self.candle_chart.candles[i];
        const ema_12 = (candle.close * M12) + (prev_ema_12 * (1 - M12));
        prev_ema_12 = ema_12;
    }

    for (26..self.candle_chart.candles.len) |i| {
        const candle = self.candle_chart.candles[i];
        const ema_12 = (candle.close * M12) + (prev_ema_12 * (1 - M12));
        const ema_26 = (candle.close * M26) + (prev_ema_26 * (1 - M26));
        prev_ema_12 = ema_12;
        prev_ema_26 = ema_26;

        const diff_ema_12_26 = ema_12 - ema_26;

        self.macd_line[(i - 26) + 1] = .{
            .x = self.candle_chart.indexToScreenX(@floatFromInt(i)),
            .y = self.toScreenY(diff_ema_12_26),
        };
    }

    for(0..26) |i| {
        self.macd_line[i] = .{
            .x = self.macd_line[26].x,
            .y = self.macd_line[26].y,
        };
    }
}

pub fn drawYAxis(self: *Self, resources: *const Resources) void {
    const r = self.layout.right();
    const price_range = self.view_y.range();
    const raw_interval = price_range / 4;
    const interval = common.niceInterval(raw_interval);
    const first = @ceil(self.view_y.min / interval) * interval;

    rl.drawRectangle(
        @intFromFloat(r),
        @intFromFloat(self.layout.top),
        @intFromFloat(charts.CandleChart.Y_AXIS_WIDTH),
        @intFromFloat(self.layout.height),
        Resources.AXIS_BG,
    );

    rl.drawLineEx(
        .{ .x = r, .y = self.layout.top },
        .{ .x = r, .y = self.layout.top + self.layout.height },
        1.0, Resources.AXIS_BORDER_COLOR,
    );

    var price = first;
    while (price <= self.view_y.max) : (price += interval) {
        const sy = self.toScreenY(price);
        const screen_y = sy;

        rl.drawLineEx(
            .{ .x = self.layout.left, .y = screen_y },
            .{ .x = r, .y = screen_y },
            1.0,
            Resources.GRID_COLOR
        );

        rl.drawLineEx(
            .{ .x = r, .y = screen_y },
            .{ .x = r + 4.0, .y = screen_y },
            1.0,
            .{ .r = 120, .g = 120, .b = 120, .a = 255 },
        );

        var buf: [16]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{price}) catch @panic("unable to convert float -> string");

        const label_x = r + 8.0;
        const label_y = screen_y - charts.CandleChart.PRICE_FONT_SIZE / 2.0;
        rl.drawTextEx(resources.font, text, .{ .x = label_x, .y = label_y }, charts.CandleChart.PRICE_FONT_SIZE, 1, .white);
    }
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, resources: *const Resources) !void {
    self.computeMACD();
    self.drawYAxis(resources);
    charts.LineChart.draw(&self.layout, self.macd_line, .{ .r = 255, .g = 0, .b = 0, .a = 255 });

    if(rl.checkCollisionPointRec(rl.getMousePosition(), self.layout.getRect())) {
        try self.candle_chart.drawCrosshair(allocator, &self.layout, &self.view_y, resources);
    }
}

fn handleEvents(self: *Self, ctx: *EventCtx) void {
    if(!ctx.tryOwnMouseDown(@ptrCast(self), self.layout.getRect())) return;

    if (ctx.isWheelScroll() and !ctx.isHorizontalScroll() and !(rl.isKeyDown(.left_shift) or rl.isKeyDown(.left_control))) {
        const cursor_price = (self.view_y.range()) / 2 + self.view_y.min;
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;

        const new_min = cursor_price + (self.view_y.min - cursor_price) * factor;
        const new_max = cursor_price + (self.view_y.max - cursor_price) * factor;
        const diff = new_max - new_min;
        if (diff > 0.001 and diff < 3_000_000_000) {
            self.view_y.min = new_min;
            self.view_y.max = new_max;
        }

        ctx.state.y_axis_resize = 1;
        return;
    }

    if (ctx.mouse_d) |mouse_d| {
        const price_per_pixel = ctx.drag_start_view_y.range() / self.layout.scaledHeight();
        self.view_y.min = ctx.drag_start_view_y.min + mouse_d.y * price_per_pixel;
        self.view_y.max = ctx.drag_start_view_y.max + mouse_d.y * price_per_pixel;
        ctx.state.y_pan = 1;
    } else if(rl.isMouseButtonDown(.left)) {
        ctx.drag_start_view_y = self.view_y;
        ctx.state.view_y = 1;
    }
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    const self: *Self = @alignCast(@ptrCast(ptr));

    if(rl.isWindowResized()) {
        self.computeLayout();
    }

    if(self.region.sib) |s| {
        try s.handleEvents(allocator, ctx);
    }

    self.handleEvents(ctx);
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, _: *EventCtx, resources: *Resources) !void {
    const self: *Self = @alignCast(@ptrCast(ptr));
    try self.draw(allocator, resources);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *Self = @alignCast(@ptrCast(ptr));
    self.deinit(allocator);
}

