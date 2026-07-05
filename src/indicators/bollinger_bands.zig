const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");

const Self = @This();
const PERIOD = 20;

sma: []f32,
upper: []f32,
lower: []f32,
candle_chart: *const charts.CandleChart,

pub fn init(allocator: std.mem.Allocator, candle_chart: *const charts.CandleChart) !Self {
    const self = Self{
        .sma = try allocator.alloc(f32, candle_chart.candles.len - PERIOD + 1),
        .upper = try allocator.alloc(f32, candle_chart.candles.len - PERIOD + 1),
        .lower = try allocator.alloc(f32, candle_chart.candles.len - PERIOD + 1),
        .candle_chart = candle_chart
    };
    self.calcBands();
    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.sma);
    allocator.free(self.upper);
    allocator.free(self.lower);
}

fn calcBands(self: *const Self) void {
    const candles = self.candle_chart.candles;
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

fn drawLine(self: *const Self, points: []f32, start_idx: usize, color: rl.Color) void {
    std.debug.assert(points.len > 1);

    rl.beginScissorMode(
        @intFromFloat(self.candle_chart.layout.left),
        @intFromFloat(self.candle_chart.layout.top),
        @intFromFloat(self.candle_chart.layout.width),
        @intFromFloat(self.candle_chart.layout.height),
    );
    defer rl.endScissorMode();

    const points_with_offset = points[start_idx..];

    var i, const end = self.candle_chart.viewXCulling(start_idx, points_with_offset.len);

    while (i < end) : (i += 1) {
        const y_start = self.candle_chart.viewToScreenY(points_with_offset[i]);
        const y_end = self.candle_chart.viewToScreenY(points_with_offset[i + 1]);
        rl.drawLineEx(
            .{ .x = self.candle_chart.indexToScreenX(@floatFromInt(i + start_idx)), .y = y_start },
            .{ .x = self.candle_chart.indexToScreenX(@floatFromInt(i + 1 + start_idx)), .y = y_end },
            1.2,
            color
        );
    }
}

pub fn draw(self: *const Self) void {
    self.drawLine(self.sma, PERIOD - 1, .white);
    self.drawLine(self.upper, PERIOD - 1, .blue);
    self.drawLine(self.lower, PERIOD - 1, .blue);
}
