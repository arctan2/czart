const std = @import("std");
const rl = @import("raylib");
const candle_chart = @import("candle_chart.zig");
const CandleChart = candle_chart.CandleChart;
const Candle = candle_chart.Candle;

pub fn main() void {
    const screen_width: i32 = 1400;
    const screen_height: i32 = 740;

    rl.initWindow(screen_width, screen_height, "candle chart");
    defer rl.closeWindow();

    var candles = [_]Candle{
        .{ .open = 120.5, .close = 125.0, .low = 118.2, .high = 128.1, .timestamp = 10 },
        .{ .open = 125.8, .close = 123.4, .low = 121.7, .high = 127.9, .timestamp = 20 },
        .{ .open = 123.4, .close = 130.2, .low = 122.8, .high = 132.5, .timestamp = 30 },
        .{ .open = 130.2, .close = 128.6, .low = 127.1, .high = 133.0, .timestamp = 40 },
        .{ .open = 128.6, .close = 135.4, .low = 126.9, .high = 137.8, .timestamp = 50 },
        .{ .open = 135.4, .close = 133.1, .low = 131.5, .high = 136.2, .timestamp = 60 },
        .{ .open = 133.1, .close = 138.9, .low = 132.4, .high = 140.7, .timestamp = 70 },
        .{ .open = 138.9, .close = 136.3, .low = 135.0, .high = 141.2, .timestamp = 80 },
        .{ .open = 136.3, .close = 142.7, .low = 134.8, .high = 145.1, .timestamp = 90 },
        .{ .open = 142.7, .close = 140.5, .low = 139.2, .high = 144.3, .timestamp = 100 },
    };
    var chart: CandleChart = .init(
        .{
            .x = 20,
            .y = 20,
            .width = screen_width - 40,
            .height = screen_height - 40,
        },
        &candles,
    );

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.{ .r = 10, .g = 10, .b = 15, .a = 255 });
        chart.handleEvents();
        chart.draw();
    }
}

