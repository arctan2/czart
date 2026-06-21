const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");
const Resources = @import("resources");

const Self = @This();

macd_line: []rl.Vector2,
signal_line: []rl.Vector2,
layout: Layout,
height_factor: f32,

pub fn init(allocator: std.mem.Allocator, candles: []charts.CandleChart.Candle) !Self {
    const self = Self{
        .macd_line = try allocator.alloc(rl.Vector2, (candles.len - 26) + 1),
        .signal_line = try allocator.alloc(rl.Vector2, (candles.len - 26) + 1),
        .layout = .{},
        .height_factor = 0.3
    };
    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.macd_line);
    allocator.free(self.signal_line);
}

fn computeMACD(self: *const Self, layout: *const Layout, candles: []charts.CandleChart.Candle) void {
    if (candles.len < 26) return;

    var sum_12: f32 = 0;
    var sum_26: f32 = 0;

    for (candles[12..24]) |candle| sum_12 += candle.close;
    for (candles[0..26]) |candle| sum_26 += candle.close;

    var prev_ema_12 = sum_12 / 12.0;
    var prev_ema_26 = sum_26 / 26.0;

    const M12: f32 = 2.0 / 13.0;
    const M26: f32 = 2.0 / 27.0;

    for (12..26) |i| {
        const candle = candles[i];
        const ema_12 = (candle.close * M12) + (prev_ema_12 * (1 - M12));
        prev_ema_12 = ema_12;
    }

    for (26..candles.len) |i| {
        const candle = candles[i];
        const ema_12 = (candle.close * M12) + (prev_ema_12 * (1 - M12));
        const ema_26 = (candle.close * M26) + (prev_ema_26 * (1 - M26));
        prev_ema_12 = ema_12;
        prev_ema_26 = ema_26;

        const diff_ema_12_26 = ema_12 - ema_26;

        self.macd_line[(i - 26) + 1] = .{
            .x = layout.indexToScreenX(@floatFromInt(i)),
            .y = layout.priceToScreenY(diff_ema_12_26),
        };
    }

    for(0..26) |i| {
        self.macd_line[i] = .{
            .x = self.macd_line[26].x,
            .y = self.macd_line[26].y,
        };
    }
}

pub fn draw(self: *Self, resources: *const Resources, candles: []charts.CandleChart.Candle) void {
    self.computeMACD(&self.layout, candles);
    self.layout.drawYAxis(resources);
    charts.LineChart.draw(&self.layout, self.macd_line, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
}

pub fn resize(self: *Self, layout: *const Layout) void {
    const new_height = layout.height * self.height_factor;
    self.layout = .{
        .height = new_height,
        .width = layout.width,
        .left = layout.left,
        .top = layout.top + layout.height * (1 - self.height_factor),
        .screen_rect = layout.screen_rect,
        .view_y = .{ .max = 10, .min = -10 }
    };
}
