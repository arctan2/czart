const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");

const Self = @This();

points: []rl.Vector2,
period: usize,

pub fn init(allocator: std.mem.Allocator, candles: []charts.CandleChart.Candle, period: usize) Self {
    const self = Self{
        .points = allocator.alloc(rl.Vector2, candles.len - period + 1) catch @panic("unable to alloc points"),
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
        .y = layout.priceToScreenY(sum / @as(f32, @floatFromInt(self.period))) + layout.chart_screen_rect.y,
    };

    for (self.period..candles.len) |i| {
        sum += candles[i].close;
        sum -= candles[i - self.period].close;

        self.points[i - self.period + 1] = .{
            .x = layout.indexToScreenX(@floatFromInt(i)),
            .y = layout.priceToScreenY(sum / @as(f32, @floatFromInt(self.period))) + layout.chart_screen_rect.y,
        };
    }
}

pub fn draw(self: *const Self, layout: *const Layout, candles: []charts.CandleChart.Candle) void {
    rl.beginScissorMode(
        @intFromFloat(layout.chartLeft()),
        @intFromFloat(layout.chartTop()),
        @intFromFloat(layout.chart_screen_rect.width),
        @intFromFloat(layout.chart_screen_rect.height),
    );
    defer rl.endScissorMode();

    self.computeSMA(layout, candles);
    rl.drawSplineLinear(self.points, 1, .blue);
}
