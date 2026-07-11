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
const DEFAULT_FAST_LEN: usize = 12;
const DEFAULT_SLOW_LEN: usize = 26;
const DEFAULT_SIGNAL_LEN: usize = 9;
const DEFAULT_KEY_SENSITIVITY = 0.2;

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

slow_len: usize = DEFAULT_SLOW_LEN,
fast_len: usize = DEFAULT_FAST_LEN,
signal_len: usize = DEFAULT_SIGNAL_LEN,

cur_edit_idx: usize = 0,
last_key_down_time: f32 = 0,
key_sensitivity: f32 = 0.2,

pub fn init(
    allocator: std.mem.Allocator,
    screen_rect: *const rl.Rectangle,
    candle_chart: *charts.CandleChart,
    above_layout: *Layout
) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .macd_y_points = try allocator.alloc(f32, (candle_chart.candles.len - DEFAULT_SLOW_LEN) + 1),
        .signal_y_points = try allocator.alloc(f32, (candle_chart.candles.len - (DEFAULT_SLOW_LEN + DEFAULT_SIGNAL_LEN)) + 1),
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
        .slow_len = DEFAULT_SLOW_LEN,
        .fast_len = DEFAULT_FAST_LEN,
        .signal_len = DEFAULT_SIGNAL_LEN,
        .key_sensitivity = DEFAULT_KEY_SENSITIVITY
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
    self.above_layout.height += self.layout.height;
    allocator.free(self.macd_y_points);
    allocator.free(self.signal_y_points);
    allocator.destroy(self);
}

fn computeMinMaxY(self: *Self) void {
    var min: f32 = std.math.inf(f32);
    var max: f32 = 0;

    for(0..self.signal_y_points.len) |i| {
        min = @min(min, self.macd_y_points[i + self.signal_len], self.signal_y_points[i]);
        max = @max(max, self.macd_y_points[i + self.signal_len], self.signal_y_points[i]);
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

pub fn reallocBuffers(self: *Self, allocator: std.mem.Allocator) !void {
    allocator.free(self.macd_y_points);
    allocator.free(self.signal_y_points);
    self.macd_y_points = try allocator.alloc(f32, (self.candle_chart.candles.len - self.slow_len) + 1);
    self.signal_y_points = try allocator.alloc(f32, (self.candle_chart.candles.len - (self.slow_len + self.signal_len)) + 1);
}

fn computeMACD(self: *const Self) void {
    if (self.candle_chart.candles.len < self.slow_len) return;

    var sum_fast: f32 = 0;
    var sum_slow: f32 = 0;

    for (self.candle_chart.candles[self.fast_len..(self.fast_len * 2)]) |candle| sum_fast += candle.close;
    for (self.candle_chart.candles[0..self.slow_len]) |candle| sum_slow += candle.close;

    var prev_ema_fast = sum_fast / @as(f32, @floatFromInt(self.fast_len));
    var prev_ema_slow = sum_slow / @as(f32, @floatFromInt(self.slow_len));

    const M_FAST: f32 = 2.0 / @as(f32, @floatFromInt(self.fast_len + 1));
    const M_SLOW: f32 = 2.0 / @as(f32, @floatFromInt(self.slow_len + 1));

    for (self.fast_len..self.slow_len) |i| {
        const candle = self.candle_chart.candles[i];
        const ema_fast = (candle.close * M_FAST) + (prev_ema_fast * (1 - M_FAST));
        prev_ema_fast = ema_fast;
    }

    for (self.slow_len..self.candle_chart.candles.len) |i| {
        const candle = self.candle_chart.candles[i];
        const ema_fast = (candle.close * M_FAST) + (prev_ema_fast * (1 - M_FAST));
        const ema_slow = (candle.close * M_SLOW) + (prev_ema_slow * (1 - M_SLOW));
        prev_ema_fast = ema_fast;
        prev_ema_slow = ema_slow;

        const diff_ema_fast_26 = ema_fast - ema_slow;

        self.macd_y_points[i - self.slow_len] = diff_ema_fast_26;
    }

    var sum: f32 = 0;

    for (self.macd_y_points[0..self.signal_len]) |p| {
        sum += p;
    }

    self.signal_y_points[0] = sum / @as(f32, @floatFromInt(self.signal_len));

    for (self.signal_len..(self.macd_y_points.len - self.signal_len)) |i| {
        sum += self.macd_y_points[i];
        sum -= self.macd_y_points[i - self.signal_len];
        self.signal_y_points[(i - self.signal_len) + 1] = sum / @as(f32, @floatFromInt(self.signal_len));
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

    var i, const end = self.candle_chart.viewXCulling(start_idx, points.len);

    while(i < end) : (i += 1) {
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
    std.debug.assert(self.macd_y_points.len == self.signal_y_points.len + self.signal_len);

    rl.beginScissorMode(
        @intFromFloat(self.layout.left),
        @intFromFloat(self.layout.top),
        @intFromFloat(self.layout.width),
        @intFromFloat(self.layout.height),
    );
    defer rl.endScissorMode();

    const macd_y_points = self.macd_y_points[8..];
    const signal_y_points = self.signal_y_points;

    var i, const end = self.candle_chart.viewXCulling(start_idx, signal_y_points.len);
    const slot_px = self.layout.width / self.candle_chart.view.x.range();
    const w = slot_px * 0.8;
    const zero_screen_y = self.toScreenY(0.0);

    var prev_diff: ?f32 = null;

    while(i < end) : (i += 1) {
        const diff = macd_y_points[i] - signal_y_points[i];

        const idx: f32 = @floatFromInt(i + start_idx);
        const sx = self.candle_chart.indexToScreenX(idx) - w / 2.0;

        if (sx + w < self.layout.left) continue;
        if (sx > self.layout.right()) continue;

        const val_screen_y = self.toScreenY(diff);

        const body_top = @min(zero_screen_y, val_screen_y);
        const body_height = @abs(zero_screen_y - val_screen_y);

        var c = if (diff > 0) rl.Color.green else rl.Color.red;

        if(prev_diff) |p| {
            if(@abs(diff) < @abs(p)) {
                c.r -|= 100;
                c.g -|= 100;
                c.b -|= 100;
            }
        }

        prev_diff = diff;

        rl.drawRectangleV(.{ .x = sx, .y = body_top }, .{ .x = w, .y = body_height }, c);
    }
}

pub fn drawTitle(self: *Self, allocator: std.mem.Allocator, resources: *const Resources, ctx: *const EventCtx) !void {
    const pad = 10;
    const font_size: f32 = 16;
    const top = self.layout.top + pad;
    const left = self.layout.left + pad;
    const param_start = resources.measureText("MACD(", font_size, 1);
    const text = try std.fmt.allocPrintSentinel(allocator, "MACD({d}, {d}, {d})", .{self.fast_len, self.slow_len, self.signal_len}, 0);
    defer allocator.free(text);
    rl.drawTextEx(resources.font, text, .{ .x = left, .y = top }, font_size, 1, .white);

    if(ctx.focused == null or ctx.focused.? != @as(*anyopaque, @ptrCast(self))) return;

    const fast_len_text = try std.fmt.allocPrintSentinel(allocator, "{d}, ", .{self.fast_len}, 0);
    defer allocator.free(fast_len_text);

    const slow_len_text = try std.fmt.allocPrintSentinel(allocator, "{d}, ", .{self.slow_len}, 0);
    defer allocator.free(slow_len_text);

    const signal_len_text = try std.fmt.allocPrintSentinel(allocator, "{d}, ", .{self.signal_len}, 0);
    defer allocator.free(signal_len_text);

    const w = switch(self.cur_edit_idx) {
        0 => resources.measureText(fast_len_text, font_size, 1).x,
        1 => resources.measureText(slow_len_text, font_size, 1).x,
        2 => resources.measureText(signal_len_text, font_size, 1).x,
        else => 0
    };

    const x = switch(self.cur_edit_idx) {
        1 => resources.measureText(fast_len_text, font_size, 1).x,
        2 => resources.measureText(fast_len_text, font_size, 1).x + resources.measureText(slow_len_text, font_size, 1).x,
        else => 0
    };

    rl.drawRectangleV(
        .{ .x = left + param_start.x + x, .y = top },
        .{ .x = w, .y = param_start.y },
        .{ .r = 255, .g = 255, .b = 255, .a = 100 }
    );
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, resources: *const Resources, ctx: *const EventCtx) !void {
    const offset = self.signal_len + self.slow_len - 1;
    self.drawYAxis(resources);
    self.drawHistogram(offset);
    self.drawLineChart(self.macd_y_points[self.signal_len..], .{ .r = 255, .g = 255, .b = 0, .a = 255 }, offset);
    self.drawLineChart(self.signal_y_points, .{ .r = 255, .g = 0, .b = 255, .a = 255 }, offset);
    try self.drawTitle(allocator, resources, ctx);

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
        }
    }
}

fn handleKeyEvents(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    if(ctx.focused != @as(*anyopaque, @ptrCast(self))) return;

    const MAX_VAL = 100;

    if(rl.isKeyPressed(.left)) {
        if(self.last_key_down_time == 0) {
            self.cur_edit_idx = if(self.cur_edit_idx == 0) 2 else self.cur_edit_idx - 1;
        }
        self.last_key_down_time += self.key_sensitivity;
    }

    if(rl.isKeyPressed(.right)) {
        if(self.last_key_down_time == 0) {
            self.cur_edit_idx = if(self.cur_edit_idx == 2) 0 else self.cur_edit_idx + 1;
        }
        self.last_key_down_time += self.key_sensitivity;
    }

    if(rl.isKeyDown(.up)) {
        if(self.last_key_down_time == 0) {
            switch(self.cur_edit_idx) {
                0 => self.fast_len = std.math.clamp(self.fast_len +| 1, 1, self.slow_len),
                1 => self.slow_len = std.math.clamp(self.slow_len +| 1, self.fast_len, MAX_VAL),
                2 => self.signal_len = std.math.clamp(self.signal_len +| 1, 1, MAX_VAL),
                else => unreachable
            }

            try self.reallocBuffers(allocator);
            self.computeMACD();
        }
        self.last_key_down_time += self.key_sensitivity;
    }

    if(rl.isKeyDown(.down)) {
        if(self.last_key_down_time == 0) {
            switch(self.cur_edit_idx) {
                0 => self.fast_len = std.math.clamp(self.fast_len -| 1, 1, self.slow_len),
                1 => self.slow_len = std.math.clamp(self.slow_len -| 1, self.fast_len, MAX_VAL),
                2 => self.signal_len = std.math.clamp(self.signal_len -| 1, 8, MAX_VAL),
                else => unreachable
            }

            try self.reallocBuffers(allocator);
            self.computeMACD();

            try self.reallocBuffers(allocator);
            self.computeMACD();
        }
        self.last_key_down_time += self.key_sensitivity;
    }

    if(EventCtx.isAnyKeyReleased(&.{ .up, .down, .left, .right })) {
        self.last_key_down_time = 0;
        self.key_sensitivity = DEFAULT_KEY_SENSITIVITY;
    } else if(self.last_key_down_time > 1) {
        self.last_key_down_time = 0;
        self.key_sensitivity += 0.2;
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

    if(ctx.state.focus == 0) {
        _ = ctx.tryFocus(ptr, self.layout.getRect());
        try self.handleKeyEvents(allocator, ctx);
    }

    self.handleEvents(ctx);
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx, resources: *Resources) !void {
    const self: *Self = @alignCast(@ptrCast(ptr));
    try self.draw(allocator, resources, ctx);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *Self = @alignCast(@ptrCast(ptr));
    self.deinit(allocator);
}

