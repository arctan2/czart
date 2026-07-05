const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");

const Self = @This();

points: []rl.Vector2,
period: usize,

pub fn init(allocator: std.mem.Allocator, candles: []charts.CandleChart.Candle, period: usize) !Self {
    const self = Self{
        .points = try allocator.alloc(rl.Vector2, candles.len - period + 1),
        .period = period
    };
    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.points);
}

fn computeEMA(self: *const Self, chart: *const charts.CandleChart) void {
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
    self.computeEMA(chart);
    charts.LineChart.draw(&chart.layout, self.points, .{ .r = 0, .g = 150, .b = 255, .a = 255 });
}
