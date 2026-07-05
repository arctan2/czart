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

macd_y_points: []f32,
signal_y_points: []f32,
layout: Layout,
region: Region,
candle_chart: *charts.CandleChart,
view_y: MinMax,
above_layout: *Layout,
drag_mode: enum { none, resize, pan } = .none,
drag_start_top: f32 = 0,
drag_start_height: f32 = 0,
drag_start_above_height: f32 = 0,

pub fn init(
    allocator: std.mem.Allocator,
    screen_rect: *const rl.Rectangle,
    candle_chart: *charts.CandleChart,
    above_layout: *Layout
) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .macd_y_points = try allocator.alloc(f32, (candle_chart.candles.len - 26) + 1),
        .signal_y_points = try allocator.alloc(f32, (candle_chart.candles.len - 26) + 1),
        .layout = .empty(screen_rect),
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .destroyFn = deinitRegion
        },
        .candle_chart = candle_chart,
        .view_y = .{ .max = 2, .min = -2 },
        .above_layout = above_layout,
    };

    self.computeLayout();
    self.computeMACD();
    self.computeMinMaxY();

    return self;
}

fn computeLayout(self: *Self) void {
    const h = self.candle_chart.layout.height;
    self.candle_chart.layout.height = h * (1 - 0.3);
    self.layout.height = h * 0.3;
    self.layout.width = self.layout.screen_rect.width - charts.CandleChart.Y_AXIS_WIDTH;
    self.layout.left = self.candle_chart.layout.left;
    self.layout.top = self.candle_chart.layout.bottom();
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.macd_y_points);
    allocator.free(self.signal_y_points);
    allocator.destroy(self);
}

fn computeMinMaxY(self: *Self) void {
    var min: f32 = std.math.inf(f32);
    var max: f32 = 0;

    for(0..self.macd_y_points.len) |i| {
        min = @min(min, self.macd_y_points[i], self.signal_y_points[i]);
        max = @max(max, self.macd_y_points[i], self.signal_y_points[i]);
    }

    self.view_y.max = max;
    self.view_y.min = min;
}

pub fn toScreenY(self: *const Self, p: f32) f32 {
    const t = (p - self.view_y.min) / self.view_y.range();
    return (self.layout.height * (1.0 - t)) + self.layout.top;
}

pub fn toViewY(self: *Self, y: f32) f32 {
    const t = 1.0 - ((y - self.layout.top) / self.layout.height);
    return self.view_y.min + t * self.view_y.range();
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

        self.macd_y_points[(i - 26) + 1] = diff_ema_12_26;
    }

    for(0..26) |i| self.macd_y_points[i] = self.macd_y_points[26];

    var sum: f32 = 0;

    for (self.macd_y_points[0..9]) |p| {
        sum += p;
    }

    self.signal_y_points[0] = sum / 9.0;

    for (9..self.macd_y_points.len) |i| {
        sum += self.macd_y_points[i];
        sum -= self.macd_y_points[i - 9];
        self.signal_y_points[(i - 9) + 1] = sum / 9.0;
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

fn drawLineChart(self: *Self, points: []f32, color: rl.Color, start_idx: usize) void {
    std.debug.assert(points.len > 1);

    rl.beginScissorMode(
        @intFromFloat(self.layout.left),
        @intFromFloat(self.layout.top),
        @intFromFloat(self.layout.width),
        @intFromFloat(self.layout.height),
    );
    defer rl.endScissorMode();

    var i: usize = start_idx;
    while(i < points.len - 1) : (i += 1) {
        const y_start = self.toScreenY(points[i]);
        const y_end = self.toScreenY(points[i + 1]);
        rl.drawLineEx(
            .{ .x = self.candle_chart.indexToScreenX(@floatFromInt(i + start_idx)), .y = y_start },
            .{ .x = self.candle_chart.indexToScreenX(@floatFromInt(i + 1 + start_idx)), .y = y_end },
            1.2,
            color
        );
    }
}

fn drawHistogram(self: *Self, start_idx: usize) void {
    std.debug.assert(self.macd_y_points.len > 1);
    std.debug.assert(self.macd_y_points.len == self.signal_y_points.len);

    rl.beginScissorMode(
        @intFromFloat(self.layout.left),
        @intFromFloat(self.layout.top),
        @intFromFloat(self.layout.width),
        @intFromFloat(self.layout.height),
    );
    defer rl.endScissorMode();

    var i: usize = start_idx;
    const slot_px = self.layout.width / self.candle_chart.view.x.range();
    const w = slot_px * 0.8;
    const zero_screen_y = self.toScreenY(0.0);

    while(i < self.macd_y_points.len) : (i += 1) {
        const diff = self.macd_y_points[i] - self.signal_y_points[i];

        const idx: f32 = @floatFromInt(i + start_idx);
        const sx = self.candle_chart.indexToScreenX(idx) - w / 2.0;

        if (sx + w < self.layout.left) continue;
        if (sx > self.layout.right()) continue;

        const val_screen_y = self.toScreenY(diff);

        const body_top = @min(zero_screen_y, val_screen_y);
        const body_height = @abs(zero_screen_y - val_screen_y);
        const c = if (diff > 0) rl.Color.green else rl.Color.red;

        rl.drawRectangleV(.{ .x = sx, .y = body_top }, .{ .x = w, .y = body_height }, c);
    }
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, resources: *const Resources) !void {
    self.computeMACD();
    self.drawYAxis(resources);
    self.drawHistogram(25);
    self.drawLineChart(self.macd_y_points, .{ .r = 255, .g = 255, .b = 0, .a = 255 }, 25);
    self.drawLineChart(self.signal_y_points, .{ .r = 255, .g = 0, .b = 255, .a = 255 }, 25);

    const is_on_divider = rl.checkCollisionPointLine(
        rl.getMousePosition(),
        .{ .x = self.layout.left, .y = self.layout.top + 4 },
        .{ .x = self.layout.right(), .y = self.layout.top + 4 },
        8
    );

    rl.drawLineEx(
        .{ .x = self.layout.left, .y = self.layout.top },
        .{ .x = self.layout.right(), .y = self.layout.top },
        if(is_on_divider or self.drag_mode == .resize) 4 else 1, .blue
    );

    if(rl.checkCollisionPointRec(rl.getMousePosition(), self.layout.getRect())) {
        try self.candle_chart.drawCrosshair(allocator, &self.layout, &self.view_y, resources);
    }
}

fn handleEvents(self: *Self, ctx: *EventCtx) void {
    const is_mouse_left_down = rl.isMouseButtonDown(.left);
    if (!is_mouse_left_down) self.drag_mode = .none;

    if(!ctx.tryOwnMouseDown(@ptrCast(self), self.layout.getRect())) return;

    const mouse = rl.getMousePosition();

    if (self.drag_mode == .none and is_mouse_left_down) {
        const is_on_divider = rl.checkCollisionPointLine(
            mouse,
            .{ .x = self.layout.left, .y = self.layout.top },
            .{ .x = self.layout.right(), .y = self.layout.top },
            8
        );
        self.drag_mode = if (is_on_divider) .resize else .pan;
        self.drag_start_top = self.layout.top;
        self.drag_start_height = self.layout.height;
        self.drag_start_above_height = self.above_layout.height;
    }

    if (self.drag_mode == .resize) {
        if(ctx.mouse_d) |mouse_d| {
            self.layout.top = self.drag_start_top + mouse_d.y;
            self.layout.height = self.drag_start_height - mouse_d.y;
            self.above_layout.height = self.drag_start_above_height + mouse_d.y;
        }
        return;
    }

    if (ctx.isWheelScroll() and !ctx.isHorizontalScroll() and !(rl.isKeyDown(.left_shift) or rl.isKeyDown(.left_control))) {
        const cursor_price = self.toViewY(mouse.y);
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;

        const new_min = cursor_price + (self.view_y.min - cursor_price) * factor;
        const new_max = cursor_price + (self.view_y.max - cursor_price) * factor;
        const diff = new_max - new_min;
        if (diff > 0.001 and diff < 3_000_000_000) {
            self.view_y.min = new_min;
            self.view_y.max = new_max;
        }

        ctx.state.view_y_resize = 1;
        return;
    }

    if(is_mouse_left_down) {
        if (ctx.mouse_d) |mouse_d| {
            const price_per_pixel = ctx.drag_start_view_y.range() / self.layout.height;
            self.view_y.min = ctx.drag_start_view_y.min + mouse_d.y * price_per_pixel;
            self.view_y.max = ctx.drag_start_view_y.max + mouse_d.y * price_per_pixel;
            ctx.state.y_pan = 1;
        } else if(rl.isMouseButtonDown(.left)) {
            ctx.drag_start_view_y = self.view_y;
            ctx.state.mouse_left_down = 1;
        }
    }
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    const self: *Self = @alignCast(@ptrCast(ptr));

    if(rl.isWindowResized()) {
        self.computeLayout();
        self.computeMinMaxY();
    }

    if(rl.isKeyPressed(.r)) {
        self.computeMinMaxY();
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

