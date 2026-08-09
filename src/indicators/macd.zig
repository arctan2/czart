const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");
const Resources = @import("resources");
const Region = @import("region");
const common = @import("common");
const defaults = @import("defaults");
const EventCtx = Region.EventCtx;
const ParamEditor = @import("param_editor.zig").ParamEditor(3);
const IndicatorRegion = @import("indicator_region.zig").IndicatorRegion(Self);

const Self = @This();
const DEFAULT_FAST_LEN: usize = 12;
const DEFAULT_SLOW_LEN: usize = 26;
const DEFAULT_SIGNAL_LEN: usize = 9;
const MACD_LINE_COLOR: rl.Color = .{ .r = 255, .g = 255, .b = 0, .a = 255 };
const SIGNAL_LINE_COLOR: rl.Color = .{ .r = 255, .g = 0, .b = 255, .a = 255 };
const HIST_POSITIVE_COLOR: rl.Color = .green;
const HIST_NEGATIVE_COLOR: rl.Color = .red;

macd_y_points: []f32,
signal_y_points: []f32,
indicator_region: *IndicatorRegion,
candle_chart: *charts.CandleChart,

slow_len: usize = DEFAULT_SLOW_LEN,
fast_len: usize = DEFAULT_FAST_LEN,
signal_len: usize = DEFAULT_SIGNAL_LEN,

editor: ParamEditor = .{},

pub fn init(
    allocator: std.mem.Allocator,
    candle_chart: *charts.CandleChart,
) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .macd_y_points = try allocator.alloc(f32, (candle_chart.candles.len - DEFAULT_SLOW_LEN) + 1),
        .signal_y_points = try allocator.alloc(f32, (candle_chart.candles.len - (DEFAULT_SLOW_LEN + DEFAULT_SIGNAL_LEN)) + 2),
        .indicator_region = undefined,
        .candle_chart = candle_chart,
        .slow_len = DEFAULT_SLOW_LEN,
        .fast_len = DEFAULT_FAST_LEN,
        .signal_len = DEFAULT_SIGNAL_LEN,
    };
    self.indicator_region = try .init(allocator, candle_chart.layout.screen_rect, self);

    return self;
}

pub fn compute(self: *Self) void {
    self.indicator_region.computeLayout();
    self.computeMACD();
    self.computeMinMaxY();
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.indicator_region.restoreAboveLayout();
    allocator.free(self.macd_y_points);
    allocator.free(self.signal_y_points);
    allocator.destroy(self.indicator_region);
    allocator.destroy(self);
}

pub fn computeMinMaxY(self: *Self) void {
    var min: f32 = std.math.inf(f32);
    var max: f32 = 0;

    for(0..self.signal_y_points.len) |i| {
        min = @min(min, self.macd_y_points[i + self.signal_len - 1], self.signal_y_points[i]);
        max = @max(max, self.macd_y_points[i + self.signal_len - 1], self.signal_y_points[i]);
    }

    self.indicator_region.view_y.max = max;
    self.indicator_region.view_y.min = min;
}

pub fn reallocBuffers(self: *Self, allocator: std.mem.Allocator) !void {
    allocator.free(self.macd_y_points);
    allocator.free(self.signal_y_points);
    self.macd_y_points = try allocator.alloc(f32, (self.candle_chart.candles.len - self.slow_len) + 1);
    self.signal_y_points = try allocator.alloc(f32, (self.candle_chart.candles.len - (self.slow_len + self.signal_len)) + 2);
}

fn computeMACD(self: *const Self) void {
    if (self.candle_chart.candles.len < self.slow_len + self.signal_len) return;

    var sum_fast: f32 = 0;
    var sum_slow: f32 = 0;

    for (self.candle_chart.candles[0..self.fast_len]) |candle| sum_fast += candle.close;
    for (self.candle_chart.candles[0..self.slow_len]) |candle| sum_slow += candle.close;

    var prev_ema_fast = sum_fast / @as(f32, @floatFromInt(self.fast_len));
    var prev_ema_slow = sum_slow / @as(f32, @floatFromInt(self.slow_len));

    const M_FAST: f32 = 2.0 / @as(f32, @floatFromInt(self.fast_len + 1));
    const M_SLOW: f32 = 2.0 / @as(f32, @floatFromInt(self.slow_len + 1));

    for (self.fast_len..self.slow_len) |i| {
        const candle = self.candle_chart.candles[i];
        prev_ema_fast = (candle.close * M_FAST) + (prev_ema_fast * (1 - M_FAST));
    }

    self.macd_y_points[0] = prev_ema_fast - prev_ema_slow;

    for (self.slow_len..self.candle_chart.candles.len) |i| {
        const candle = self.candle_chart.candles[i];
        const ema_fast = (candle.close * M_FAST) + (prev_ema_fast * (1 - M_FAST));
        const ema_slow = (candle.close * M_SLOW) + (prev_ema_slow * (1 - M_SLOW));
        prev_ema_fast = ema_fast;
        prev_ema_slow = ema_slow;

        self.macd_y_points[i - self.slow_len + 1] = ema_fast - ema_slow;
    }

    var sum: f32 = 0;

    for (self.macd_y_points[0..self.signal_len]) |p| {
        sum += p;
    }

    self.signal_y_points[0] = sum / @as(f32, @floatFromInt(self.signal_len));

    for (self.signal_len..self.macd_y_points.len) |i| {
        sum += self.macd_y_points[i];
        sum -= self.macd_y_points[i - self.signal_len];
        self.signal_y_points[(i - self.signal_len) + 1] = sum / @as(f32, @floatFromInt(self.signal_len));
    }
}

fn drawHistogram(self: *Self, start_idx: usize) void {
    std.debug.assert(self.macd_y_points.len > 1);
    std.debug.assert(self.macd_y_points.len == self.signal_y_points.len + self.signal_len - 1);

    const layout = &self.indicator_region.layout;
    layout.beginScissorMode();
    defer rl.endScissorMode();

    const macd_y_points = self.macd_y_points[self.signal_len - 1 ..];
    const signal_y_points = self.signal_y_points;

    var i, const end = self.candle_chart.viewXCulling(start_idx, signal_y_points.len + 1);
    const slot_px = layout.width / self.candle_chart.view.x.range();
    const w = slot_px * 0.8;
    const zero_screen_y = self.indicator_region.toScreenY(0.0);

    var prev_diff: ?f32 = null;

    while(i < end) : (i += 1) {
        const diff = macd_y_points[i] - signal_y_points[i];

        const idx: f32 = @floatFromInt(i + start_idx);
        const sx = self.candle_chart.indexToScreenX(idx) - w / 2.0;

        if (sx + w < layout.left) continue;
        if (sx > layout.right()) continue;

        const val_screen_y = self.indicator_region.toScreenY(diff);

        const body_top = @min(zero_screen_y, val_screen_y);
        const body_height = @abs(zero_screen_y - val_screen_y);

        var c = if (diff > 0) HIST_POSITIVE_COLOR else HIST_NEGATIVE_COLOR;

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

fn hoveredValues(self: *const Self) ?struct { macd: f32, signal: f32, hist: f32 } {
    if (self.signal_y_points.len == 0) return null;

    const offset = self.signal_len + self.slow_len - 2;
    const idx = self.candle_chart.getClosestCandleIdx(rl.getMousePosition().x);
    if (idx < @as(f32, @floatFromInt(offset))) return null;

    const i: usize = @intFromFloat(idx - @as(f32, @floatFromInt(offset)));
    if (i >= self.signal_y_points.len) return null;

    const macd_val = self.macd_y_points[self.signal_len - 1 + i];
    const signal_val = self.signal_y_points[i];

    return .{ .macd = macd_val, .signal = signal_val, .hist = macd_val - signal_val };
}

pub fn drawLabel(self: *Self, allocator: std.mem.Allocator, resources: *const Resources, ctx: *const EventCtx) !void {
    const pad = 10;
    const top = self.indicator_region.layout.top + pad;
    const left = self.indicator_region.layout.left + pad;
    const is_focused = ctx.focused != null and ctx.focused.? == @as(*anyopaque, @ptrCast(self));

    try self.editor.drawLabel(
        allocator, "MACD", .{ self.fast_len, self.slow_len, self.signal_len },
        .{ .x = left, .y = top }, resources, is_focused
    );

    if (self.hoveredValues()) |v| {
        const font_size = defaults.INDICATOR_FONT_SIZE;
        const prefix_text = try std.fmt.allocPrintSentinel(
            allocator, "MACD({d}, {d}, {d})", .{ self.fast_len, self.slow_len, self.signal_len }, 0
        );
        defer allocator.free(prefix_text);
        var value_x = left + resources.measureText(prefix_text, font_size, 1).x + 8;

        var macd_buf: [16]u8 = undefined;
        var signal_buf: [16]u8 = undefined;
        var hist_buf: [16]u8 = undefined;

        const macd_text = std.fmt.bufPrintZ(&macd_buf, "{d:.4}", .{v.macd}) catch return;
        rl.drawTextEx(resources.font, macd_text, .{ .x = value_x, .y = top }, font_size, 1, MACD_LINE_COLOR);
        value_x += resources.measureText(macd_text, font_size, 1).x + 8;

        const signal_text = std.fmt.bufPrintZ(&signal_buf, "{d:.4}", .{v.signal}) catch return;
        rl.drawTextEx(resources.font, signal_text, .{ .x = value_x, .y = top }, font_size, 1, SIGNAL_LINE_COLOR);
        value_x += resources.measureText(signal_text, font_size, 1).x + 8;

        const hist_text = std.fmt.bufPrintZ(&hist_buf, "{d:.4}", .{v.hist}) catch return;
        const hist_color = if (v.hist > 0) HIST_POSITIVE_COLOR else HIST_NEGATIVE_COLOR;
        rl.drawTextEx(resources.font, hist_text, .{ .x = value_x, .y = top }, font_size, 1, hist_color);
    }
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, resources: *const Resources, ctx: *const EventCtx) !void {
    const offset = self.signal_len + self.slow_len - 2;
    self.indicator_region.drawYAxis(resources, true);
    self.drawHistogram(offset);
    self.indicator_region.drawLineChart(self.candle_chart, self.macd_y_points[self.signal_len - 1 ..], MACD_LINE_COLOR, offset);
    self.indicator_region.drawLineChart(self.candle_chart, self.signal_y_points, SIGNAL_LINE_COLOR, offset);
    try self.drawLabel(allocator, resources, ctx);

    try self.indicator_region.drawResizeLineHover(allocator, self.candle_chart, resources);
}

pub fn handleKeyEvents(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    if(ctx.focused != @as(*anyopaque, @ptrCast(self))) return;

    var params = [3]usize{ self.fast_len, self.slow_len, self.signal_len };
    const changed = self.editor.handleKeyEvent(
        &params,
        .{ 1, self.fast_len, 1 },
        .{ self.slow_len, defaults.MAX_PERIOD, defaults.MAX_PERIOD },
    );
    self.fast_len = params[0];
    self.slow_len = params[1];
    self.signal_len = params[2];

    if (changed) {
        try self.reallocBuffers(allocator);
        self.computeMACD();
    }
}
