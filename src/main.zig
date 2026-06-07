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

    var candles_1d = [_]Candle{
        .{ .open = 120.5, .close = 125.0, .low = 118.2, .high = 128.1, .timestamp = 1735689600000 }, // Jan 1, 2025
        .{ .open = 125.8, .close = 123.4, .low = 121.7, .high = 127.9, .timestamp = 1735776000000 },
        .{ .open = 123.4, .close = 130.2, .low = 122.8, .high = 132.5, .timestamp = 1735862400000 },
        .{ .open = 130.2, .close = 128.6, .low = 127.1, .high = 133.0, .timestamp = 1735948800000 },
        .{ .open = 128.6, .close = 135.4, .low = 126.9, .high = 137.8, .timestamp = 1736035200000 },
        .{ .open = 135.4, .close = 133.1, .low = 131.5, .high = 136.2, .timestamp = 1736121600000 },
        .{ .open = 133.1, .close = 138.9, .low = 132.4, .high = 140.7, .timestamp = 1736208000000 },
        .{ .open = 138.9, .close = 136.3, .low = 135.0, .high = 141.2, .timestamp = 1736294400000 },
        .{ .open = 136.3, .close = 142.7, .low = 134.8, .high = 145.1, .timestamp = 1736380800000 },
        .{ .open = 142.7, .close = 140.5, .low = 139.2, .high = 144.3, .timestamp = 1736467200000 }, // Jan 10, 2025
    };
    
    // var candles_5d = [_]Candle{
    //     .{ .open = 120.5, .close = 135.4, .low = 118.2, .high = 137.8, .timestamp = 1735689600000 },
    //     .{ .open = 135.4, .close = 140.5, .low = 131.5, .high = 145.1, .timestamp = 1736121600000 },
    //     .{ .open = 140.5, .close = 144.2, .low = 138.0, .high = 146.5, .timestamp = 1736553600000 },
    //     .{ .open = 144.2, .close = 142.1, .low = 140.5, .high = 148.0, .timestamp = 1736985600000 },
    //     .{ .open = 142.1, .close = 149.5, .low = 139.8, .high = 151.2, .timestamp = 1737417600000 },
    //     .{ .open = 149.5, .close = 153.0, .low = 147.2, .high = 155.4, .timestamp = 1737849600000 },
    //     .{ .open = 153.0, .close = 151.2, .low = 149.0, .high = 157.1, .timestamp = 1738281600000 },
    //     .{ .open = 151.2, .close = 158.6, .low = 148.5, .high = 160.3, .timestamp = 1738713600000 },
    //     .{ .open = 158.6, .close = 156.4, .low = 154.1, .high = 162.0, .timestamp = 1739145600000 },
    //     .{ .open = 156.4, .close = 161.8, .low = 153.9, .high = 164.5, .timestamp = 1739577600000 },
    // };

    // var candles_1m = [_]Candle{
    //     .{ .open = 120.5, .close = 140.5, .low = 118.2, .high = 145.1, .timestamp = 1735689600000 }, // Jan 2025
    //     .{ .open = 140.5, .close = 148.2, .low = 137.5, .high = 152.0, .timestamp = 1737504000000 }, // Feb 2025
    //     .{ .open = 148.2, .close = 155.9, .low = 145.1, .high = 159.4, .timestamp = 1739318400000 },
    //     .{ .open = 155.9, .close = 153.1, .low = 150.2, .high = 162.3, .timestamp = 1741132800000 },
    //     .{ .open = 153.1, .close = 161.4, .low = 149.8, .high = 165.0, .timestamp = 1742947200000 },
    //     .{ .open = 161.4, .close = 168.7, .low = 158.0, .high = 172.1, .timestamp = 1744761600000 },
    //     .{ .open = 168.7, .close = 166.0, .low = 163.2, .high = 174.5, .timestamp = 1746576000000 },
    //     .{ .open = 166.0, .close = 173.8, .low = 162.5, .high = 178.2, .timestamp = 1748390400000 },
    //     .{ .open = 173.8, .close = 171.2, .low = 168.9, .high = 181.0, .timestamp = 1750204800000 },
    //     .{ .open = 171.2, .close = 179.5, .low = 169.1, .high = 184.3, .timestamp = 1752019200000 }, // Oct 2025
    // };

    // var candles_3m = [_]Candle{
    //     .{ .open = 120.5, .close = 155.9, .low = 118.2, .high = 159.4, .timestamp = 1735689600000 }, // Q1 2025
    //     .{ .open = 155.9, .close = 168.7, .low = 149.8, .high = 172.1, .timestamp = 1741132800000 }, // Q2 2025
    //     .{ .open = 168.7, .close = 179.5, .low = 162.5, .high = 184.3, .timestamp = 1746576000000 },
    //     .{ .open = 179.5, .close = 186.2, .low = 175.0, .high = 191.5, .timestamp = 1752019200000 },
    //     .{ .open = 186.2, .close = 194.8, .low = 181.4, .high = 199.0, .timestamp = 1757462400000 },
    //     .{ .open = 194.8, .close = 191.1, .low = 188.3, .high = 203.4, .timestamp = 1762905600000 },
    //     .{ .open = 191.1, .close = 202.5, .low = 187.0, .high = 208.1, .timestamp = 1768348800000 },
    //     .{ .open = 202.5, .close = 211.3, .low = 199.2, .high = 215.6, .timestamp = 1773792000000 },
    //     .{ .open = 211.3, .close = 208.0, .low = 204.5, .high = 219.0, .timestamp = 1779235200000 },
    //     .{ .open = 208.0, .close = 218.4, .low = 202.1, .high = 223.7, .timestamp = 1784678400000 }, // Q2 2026
    // };

    // var candles_1y = [_]Candle{
    //     .{ .open = 120.5, .close = 186.2, .low = 118.2, .high = 191.5, .timestamp = 1735689600000 }, // Year 2025
    //     .{ .open = 186.2, .close = 218.4, .low = 181.4, .high = 223.7, .timestamp = 1757462400000 }, // Year 2026
    //     .{ .open = 218.4, .close = 242.1, .low = 211.0, .high = 248.6, .timestamp = 1779235200000 },
    //     .{ .open = 242.1, .close = 237.5, .low = 231.4, .high = 252.0, .timestamp = 1801008000000 },
    //     .{ .open = 237.5, .close = 258.9, .low = 229.0, .high = 264.3, .timestamp = 1822780800000 },
    //     .{ .open = 258.9, .close = 274.2, .low = 251.3, .high = 281.0, .timestamp = 1844553600000 },
    //     .{ .open = 274.2, .close = 269.0, .low = 262.7, .high = 286.5, .timestamp = 1866326400000 },
    //     .{ .open = 269.0, .close = 291.4, .low = 258.1, .high = 297.3, .timestamp = 1888099200000 },
    //     .{ .open = 291.4, .close = 285.3, .low = 279.0, .high = 304.1, .timestamp = 1909872000000 },
    //     .{ .open = 285.3, .close = 312.0, .low = 277.5, .high = 318.5, .timestamp = 1931644800000 }, // Year 2034
    // };

    var chart: CandleChart = .init(
        .{
            .x = 20,
            .y = 20,
            .width = screen_width - 40,
            .height = screen_height - 40,
        },
        &candles_1d,
        0.05
    );

    rl.setTargetFPS(60);

    for(0..1000) |_| {
        chart.scroll(-0.1, false, true);
    }

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.{ .r = 10, .g = 10, .b = 15, .a = 255 });
        chart.handleEvents();
        chart.draw();
    }
}

