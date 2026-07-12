const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Resources = @import("resources");
const ParamEditor = @import("param_editor.zig").ParamEditor(1);
const defaults = @import("defaults");

const Self = @This();

points: []rl.Vector2,
period: usize,
candle_chart: *const charts.CandleChart,
editor: ParamEditor = .{},

pub fn init(allocator: std.mem.Allocator, candle_chart: *const charts.CandleChart, period: usize) !Self {
    const self = Self{
        .points = try allocator.alloc(rl.Vector2, candle_chart.candles.len - period + 1),
        .period = period,
        .candle_chart = candle_chart,
    };
    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.points);
}

fn reallocBuffers(self: *Self, allocator: std.mem.Allocator) !void {
    allocator.free(self.points);
    self.points = try allocator.alloc(rl.Vector2, self.candle_chart.candles.len - self.period + 1);
}

fn computeEMA(self: *const Self) void {
    const chart = self.candle_chart;
    const candles = chart.candles;
    if (candles.len < self.period) return;

    var sum: f32 = 0;

    for (candles[0..self.period]) |candle| {
        sum += candle.close;
    }

    var prev_ema = sum / @as(f32, @floatFromInt(self.period));

    self.points[0] = .{
        .x = chart.indexToScreenX(@floatFromInt(self.period - 1)),
        .y = chart.viewToScreenY(prev_ema),
    };

    const M: f32 = 2.0 / @as(f32, @floatFromInt(self.period + 1));

    for (self.period..candles.len) |i| {
        const candle = candles[i];
        const ema = (candle.close * M) + (prev_ema * (1 - M));
        prev_ema = ema;

        self.points[i - self.period + 1] = .{
            .x = chart.indexToScreenX(@floatFromInt(i)),
            .y = chart.viewToScreenY(ema),
        };
    }
}

pub fn draw(self: *const Self, chart: *const charts.CandleChart) void {
    self.computeEMA();
    charts.LineChart.draw(&chart.layout, self.points, .{ .r = 0, .g = 150, .b = 255, .a = 255 });
}

fn hoveredValue(self: *const Self) ?f32 {
    const chart = self.candle_chart;
    if (self.points.len == 0) return null;

    const idx = chart.getClosestCandleIdx(rl.getMousePosition().x);
    if (idx < @as(f32, @floatFromInt(self.period - 1))) return null;

    const point_idx: usize = @intFromFloat(idx - @as(f32, @floatFromInt(self.period - 1)));
    if (point_idx >= self.points.len) return null;

    return charts.CandleChart.screenToViewY(&chart.layout, &chart.view.y, self.points[point_idx].y);
}

pub fn drawLabel(
    self: *const Self,
    allocator: std.mem.Allocator,
    start: rl.Vector2,
    is_focused: bool,
    resources: *Resources,
) !bool {
    try self.editor.drawLabel(allocator, "EMA", .{ self.period }, start, resources, is_focused);

    if (self.hoveredValue()) |value| {
        const font_size = defaults.INDICATOR_FONT_SIZE;
        var text_buf: [16]u8 = undefined;
        const prefix_text = try std.fmt.allocPrintSentinel(allocator, "EMA({d})", .{self.period}, 0);
        defer allocator.free(prefix_text);
        const prefix_w = resources.measureText(prefix_text, font_size, 1).x;
        const text = std.fmt.bufPrintZ(&text_buf, "{d:.2}", .{value}) catch return true;
        rl.drawTextEx(
            resources.font,
            text,
            .{ .x = start.x + prefix_w + 8, .y = start.y },
            font_size, 1,
            .{ .r = 0, .g = 150, .b = 255, .a = 255 },
        );
    }

    return true;
}

pub fn handleEvents(self: *Self, allocator: std.mem.Allocator) !void {
    var params = [1]usize{ self.period };
    const changed = self.editor.handleKeyEvent(&params, .{1}, .{defaults.MAX_PERIOD});
    self.period = params[0];

    if (changed) {
        try self.reallocBuffers(allocator);
        self.computeEMA();
    }
}
