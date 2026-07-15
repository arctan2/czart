const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");
const Resources = @import("resources");
const ParamEditor = @import("param_editor.zig").ParamEditor(2);
const defaults = @import("defaults");

const Self = @This();

const STDDEV_MULT_TENTHS = 20;
const MAX_STDDEV_MULT_TENTHS = 100;

const SMA_LINE_COLOR: rl.Color = .white;
const UPPER_LINE_COLOR: rl.Color = .purple;
const LOWER_LINE_COLOR: rl.Color = .blue;
const BAND_FILL_COLOR: rl.Color = .{ .r = 0, .g = 120, .b = 255, .a = 30 };

sma: []f32,
upper: []f32,
lower: []f32,
candle_chart: *const charts.CandleChart,
period: usize,
stddev_mult_tenths: usize,
editor: ParamEditor = .{},

pub fn init(allocator: std.mem.Allocator, candle_chart: *const charts.CandleChart) !Self {
    const self = Self{
        .sma = try allocator.alloc(f32, candle_chart.candles.len - defaults.PERIOD + 1),
        .upper = try allocator.alloc(f32, candle_chart.candles.len - defaults.PERIOD + 1),
        .lower = try allocator.alloc(f32, candle_chart.candles.len - defaults.PERIOD + 1),
        .candle_chart = candle_chart,
        .period = defaults.PERIOD,
        .stddev_mult_tenths = STDDEV_MULT_TENTHS,
    };
    self.calcBands();
    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.sma);
    allocator.free(self.upper);
    allocator.free(self.lower);
}

fn reallocBuffers(self: *Self, allocator: std.mem.Allocator) !void {
    allocator.free(self.sma);
    allocator.free(self.upper);
    allocator.free(self.lower);
    self.sma = try allocator.alloc(f32, self.candle_chart.candles.len - self.period + 1);
    self.upper = try allocator.alloc(f32, self.candle_chart.candles.len - self.period + 1);
    self.lower = try allocator.alloc(f32, self.candle_chart.candles.len - self.period + 1);
}

fn stddevMult(self: *const Self) f64 {
    return @as(f64, @floatFromInt(self.stddev_mult_tenths)) / 10.0;
}

fn calcBands(self: *const Self) void {
    const candles = self.candle_chart.candles;
    if (candles.len < self.period) return;

    const mult = self.stddevMult();

    var sum: f64 = 0;
    var sum_sq: f64 = 0;

    for (candles[0..self.period]) |candle| {
        const c: f64 = candle.close;
        sum += c;
        sum_sq += c * c;
    }

    const period_f: f64 = @floatFromInt(self.period);
    var mean = sum / period_f;
    var variance = @max(0.0, (sum_sq / period_f) - (mean * mean));
    var stddev = std.math.sqrt(variance);

    self.sma[0] = @floatCast(mean);
    self.upper[0] = @floatCast(mean + mult * stddev);
    self.lower[0] = @floatCast(mean - mult * stddev);

    for (self.period..candles.len) |i| {
        const in: f64 = candles[i].close;
        const out: f64 = candles[i - self.period].close;

        sum += in - out;
        sum_sq += in * in - out * out;

        const idx = i - self.period + 1;
        mean = sum / period_f;
        variance = @max(0.0, (sum_sq / period_f) - (mean * mean));
        stddev = std.math.sqrt(variance);

        self.sma[idx] = @floatCast(mean);
        self.upper[idx] = @floatCast(mean + mult * stddev);
        self.lower[idx] = @floatCast(mean - mult * stddev);
    }
}

fn drawLine(self: *const Self, points: []f32, offset_idx: usize, color: rl.Color) void {
    std.debug.assert(points.len > 1);

    self.candle_chart.layout.beginScissorMode();
    defer rl.endScissorMode();

    var i, const end = self.candle_chart.viewXCulling(offset_idx, points.len);

    while (i < end) : (i += 1) {
        const y_start = self.candle_chart.viewToScreenY(points[i]);
        const y_end = self.candle_chart.viewToScreenY(points[i + 1]);
        rl.drawLineEx(
            .{ .x = self.candle_chart.indexToScreenX(@floatFromInt(i + offset_idx)), .y = y_start },
            .{ .x = self.candle_chart.indexToScreenX(@floatFromInt(i + 1 + offset_idx)), .y = y_end },
            1.2,
            color
        );
    }
}

fn drawBand(self: *const Self, offset_idx: usize, color: rl.Color) void {
    std.debug.assert(self.upper.len > 1);

    self.candle_chart.layout.beginScissorMode();
    defer rl.endScissorMode();

    const upper = self.upper;
    const lower = self.lower;

    var i, const end = self.candle_chart.viewXCulling(offset_idx, upper.len);

    while (i < end) : (i += 1) {
        const x0 = self.candle_chart.indexToScreenX(@floatFromInt(i + offset_idx));
        const x1 = self.candle_chart.indexToScreenX(@floatFromInt(i + 1 + offset_idx));

        const tl = rl.Vector2{ .x = x0, .y = self.candle_chart.viewToScreenY(upper[i]) };
        const tr = rl.Vector2{ .x = x1, .y = self.candle_chart.viewToScreenY(upper[i + 1]) };
        const bl = rl.Vector2{ .x = x0, .y = self.candle_chart.viewToScreenY(lower[i]) };
        const br = rl.Vector2{ .x = x1, .y = self.candle_chart.viewToScreenY(lower[i + 1]) };

        rl.drawTriangle(tl, bl, br, color);
        rl.drawTriangle(tl, br, tr, color);
    }
}

pub fn draw(self: *const Self) void {
    self.drawBand(self.period - 1, BAND_FILL_COLOR);
    self.drawLine(self.sma, self.period - 1, SMA_LINE_COLOR);
    self.drawLine(self.upper, self.period - 1, UPPER_LINE_COLOR);
    self.drawLine(self.lower, self.period - 1, LOWER_LINE_COLOR);
}

fn hoveredValues(self: *const Self) ?struct { sma: f32, upper: f32, lower: f32 } {
    const chart = self.candle_chart;
    if (self.sma.len == 0) return null;

    const idx = chart.getClosestCandleIdx(rl.getMousePosition().x);
    if (idx < @as(f32, @floatFromInt(self.period - 1))) return null;

    const point_idx: usize = @intFromFloat(idx - @as(f32, @floatFromInt(self.period - 1)));
    if (point_idx >= self.sma.len) return null;

    return .{ .sma = self.sma[point_idx], .upper = self.upper[point_idx], .lower = self.lower[point_idx] };
}

pub fn drawLabel(
    self: *const Self,
    allocator: std.mem.Allocator,
    start: rl.Vector2,
    is_focused: bool,
    resources: *Resources,
) !bool {
    const font_size: f32 = 16;
    const text = try std.fmt.allocPrintSentinel(
        allocator, "BB({d}, {d:.1})", .{ self.period, self.stddevMult() }, 0
    );
    defer allocator.free(text);
    rl.drawTextEx(resources.font, text, start, font_size, 1, .white);

    var value_x = start.x + resources.measureText(text, font_size, 1).x + 8;
    if (self.hoveredValues()) |v| {
        var sma_buf: [16]u8 = undefined;
        var upper_buf: [16]u8 = undefined;
        var lower_buf: [16]u8 = undefined;

        const sma_text = std.fmt.bufPrintZ(&sma_buf, "{d:.2}", .{v.sma}) catch return true;
        rl.drawTextEx(resources.font, sma_text, .{ .x = value_x, .y = start.y }, font_size, 1, SMA_LINE_COLOR);
        value_x += resources.measureText(sma_text, font_size, 1).x + 8;

        const upper_text = std.fmt.bufPrintZ(&upper_buf, "{d:.2}", .{v.upper}) catch return true;
        rl.drawTextEx(resources.font, upper_text, .{ .x = value_x, .y = start.y }, font_size, 1, UPPER_LINE_COLOR);
        value_x += resources.measureText(upper_text, font_size, 1).x + 8;

        const lower_text = std.fmt.bufPrintZ(&lower_buf, "{d:.2}", .{v.lower}) catch return true;
        rl.drawTextEx(resources.font, lower_text, .{ .x = value_x, .y = start.y }, font_size, 1, LOWER_LINE_COLOR);
    }

    if(!is_focused) return true;

    const prefix_w = resources.measureText("BB(", font_size, 1).x;
    const period_text = try std.fmt.allocPrintSentinel(allocator, "{d}, ", .{self.period}, 0);
    defer allocator.free(period_text);
    const mult_text = try std.fmt.allocPrintSentinel(allocator, "{d:.1}", .{self.stddevMult()}, 0);
    defer allocator.free(mult_text);

    const period_w = resources.measureText(period_text, font_size, 1).x;
    const mult_w = resources.measureText(mult_text, font_size, 1).x;

    const x = if (self.editor.cur_edit_idx == 1) period_w else 0;
    const w = if (self.editor.cur_edit_idx == 1) mult_w else period_w;

    rl.drawRectangleV(
        .{ .x = start.x + prefix_w + x, .y = start.y },
        .{ .x = w, .y = resources.measureText("BB(", font_size, 1).y },
        .{ .r = 255, .g = 255, .b = 255, .a = 100 }
    );

    return true;
}

pub fn handleEvents(self: *Self, allocator: std.mem.Allocator) !void {
    var params = [2]usize{ self.period, self.stddev_mult_tenths };
    const changed = self.editor.handleKeyEvent(&params, .{ 1, 1 }, .{ defaults.MAX_PERIOD, MAX_STDDEV_MULT_TENTHS });
    self.period = params[0];
    self.stddev_mult_tenths = params[1];

    if (changed) {
        try self.reallocBuffers(allocator);
        self.calcBands();
    }
}
