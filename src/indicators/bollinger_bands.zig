const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");

const Self = @This();
const PERIOD = 20;

sma: []f32,
upper: []f32,
lower: []f32,

pub fn init(allocator: std.mem.Allocator, candles: []charts.CandleChart.Candle) !Self {
    const self = Self{
        .sma = try allocator.alloc(f32, candles.len - PERIOD + 1),
        .upper = try allocator.alloc(f32, candles.len - PERIOD + 1),
        .lower = try allocator.alloc(f32, candles.len - PERIOD + 1),
    };
    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.sma);
    allocator.free(self.upper);
    allocator.free(self.lower);
}

fn calcBands(self: *const Self, chart: *const charts.CandleChart) void {
    const candles = chart.candles;
    if (candles.len < PERIOD) return;

    var sum: f64 = 0;
    var sum_sq: f64 = 0;

    for (candles[0..PERIOD]) |candle| {
        const c: f64 = candle.close;
        sum += c;
        sum_sq += c * c;
    }

    var mean = sum / PERIOD;
    var variance = @max(0.0, (sum_sq / PERIOD) - (mean * mean));
    var stddev = std.math.sqrt(variance);

    self.sma[0] = @floatCast(mean);
    self.upper[0] = @floatCast(mean + 2 * stddev);
    self.lower[0] = @floatCast(mean - 2 * stddev);

    for (PERIOD..candles.len) |i| {
        const in: f64 = candles[i].close;
        const out: f64 = candles[i - PERIOD].close;

        sum += in - out;
        sum_sq += in * in - out * out;

        const idx = i - PERIOD + 1;
        mean = sum / PERIOD;
        variance = @max(0.0, (sum_sq / PERIOD) - (mean * mean));
        stddev = std.math.sqrt(variance);

        self.sma[idx] = @floatCast(mean);
        self.upper[idx] = @floatCast(mean + 2 * stddev);
        self.lower[idx] = @floatCast(mean - 2 * stddev);
    }
}

fn drawLine(candle_chart: *const charts.CandleChart, points: []f32, start_idx: usize, color: rl.Color) void {
    std.debug.assert(points.len > 1);

    rl.beginScissorMode(
        @intFromFloat(candle_chart.layout.left),
        @intFromFloat(candle_chart.layout.top),
        @intFromFloat(candle_chart.layout.width),
        @intFromFloat(candle_chart.layout.height),
    );
    defer rl.endScissorMode();

    var i: usize = 0;
    while(i < points.len - 1) : (i += 1) {
        const y_start = candle_chart.viewToScreenY(points[i]);
        const y_end = candle_chart.viewToScreenY(points[i + 1]);
        rl.drawLineEx(
            .{ .x = candle_chart.indexToScreenX(@floatFromInt(i + start_idx)), .y = y_start },
            .{ .x = candle_chart.indexToScreenX(@floatFromInt(i + 1 + start_idx)), .y = y_end },
            1.2,
            color
        );
    }
}

pub fn draw(self: *const Self, chart: *const charts.CandleChart) void {
    self.calcBands(chart);
    drawLine(chart, self.sma, PERIOD - 1, .white);
    drawLine(chart, self.upper, PERIOD - 1, .blue);
    drawLine(chart, self.lower, PERIOD - 1, .blue);
}
