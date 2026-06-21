const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");

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

fn computeSMA(self: *const Self, layout: *const Layout, candles: []charts.CandleChart.Candle) void {
    if (candles.len < self.period) return;

    var sum: f32 = 0;

    for (candles[0..self.period]) |candle| {
        sum += candle.close;
    }

    self.points[0] = .{
        .x = layout.indexToScreenX(@floatFromInt(self.period - 1)),
        .y = layout.priceToScreenY(sum / @as(f32, @floatFromInt(self.period))),
    };

    for (self.period..candles.len) |i| {
        sum += candles[i].close;
        sum -= candles[i - self.period].close;

        self.points[i - self.period + 1] = .{
            .x = layout.indexToScreenX(@floatFromInt(i)),
            .y = layout.priceToScreenY(sum / @as(f32, @floatFromInt(self.period))),
        };
    }
}

pub fn draw(self: *const Self, layout: *const Layout, candles: []charts.CandleChart.Candle) void {
    self.computeSMA(layout, candles);
    charts.LineChart.draw(layout, self.points, .{ .r = 150, .g = 150, .b = 255, .a = 255 });
}
