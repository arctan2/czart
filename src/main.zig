const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const CandleChart = charts.CandleChart;
const Root = @import("root.zig");
const csvz = @import("csvzero");

pub fn parseDatetimeToTimestamp(str: []const u8) !u64 {
    if (str.len < 19) return error.InvalidFormat;

    const year = try std.fmt.parseInt(i64, str[0..4], 10);
    const month = try std.fmt.parseInt(i64, str[5..7], 10);
    const day = try std.fmt.parseInt(i64, str[8..10], 10);
    const hours = try std.fmt.parseInt(i64, str[11..13], 10);
    const minutes = try std.fmt.parseInt(i64, str[14..16], 10);
    const seconds = try std.fmt.parseInt(i64, str[17..19], 10);

    if (month < 1 or month > 12) return error.InvalidMonth;
    if (day < 1 or day > 31) return error.InvalidDay;
    if (hours > 23 or minutes > 59 or seconds > 59) return error.InvalidTime;

    const days_since_epoch = daysFromCivil(year, month, day);

    const total_seconds = days_since_epoch * 86400 +
        hours * 3600 +
        minutes * 60 +
        seconds;

    return @intCast(total_seconds * 1000);
}

fn daysFromCivil(y: i64, m: i64, d: i64) i64 {
    const yy = y - @as(i64, if (m <= 2) 1 else 0);
    const era = @divFloor(if (yy >= 0) yy else yy - 399, 400);
    const yoe = yy - era * 400;
    const mp = @mod(m + 9, 12);
    const doy = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const screen_width: i32 = 1400;
    const screen_height: i32 = 740;

    rl.setConfigFlags(.{ .window_highdpi = true, .window_maximized = true, .window_resizable = true });

    rl.initWindow(screen_width, screen_height, "candle chart");
    defer rl.closeWindow();

    rl.setExitKey(.comma);

    var file = try std.Io.Dir.cwd().openFile(io, "./datasets/ADANIENT_minute.csv", .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [64 * 1024]u8 = undefined;
    var reader = file.reader(io, &buffer);
    var it = csvz.Iterator.init(&reader.interface);

    var candles = try std.ArrayList(CandleChart.Candle).initCapacity(gpa, 512);
    defer candles.deinit(gpa);

    var rows: usize = 2500;

    for(0..6 * 4000) |_| {
        _ = it.next() catch {};
    }

    while (rows > 0) : (rows -= 1) {
        var raw_date = it.next() catch |err| switch (err) {
            error.EOF => break,
            else => return err,
        };
        var raw_open = it.next() catch |err| switch (err) {
            error.EOF => break,
            else => return err,
        };
        var raw_high = it.next() catch |err| switch (err) {
            error.EOF => break,
            else => return err,
        };
        var raw_low = it.next() catch |err| switch (err) {
            error.EOF => break,
            else => return err,
        };
        var raw_close = it.next() catch |err| switch (err) {
            error.EOF => break,
            else => return err,
        };
        var raw_volume = it.next() catch |err| switch (err) {
            error.EOF => break,
            else => return err,
        };

        const timestamp = try parseDatetimeToTimestamp(raw_date.unescaped());
        const open = try std.fmt.parseFloat(f32, raw_open.unescaped());
        const high = try std.fmt.parseFloat(f32, raw_high.unescaped());
        const low = try std.fmt.parseFloat(f32, raw_low.unescaped());
        const close = try std.fmt.parseFloat(f32, raw_close.unescaped());
        const volume = try std.fmt.parseFloat(f32, raw_volume.unescaped());

        const candle: CandleChart.Candle = .{
            .open = open,
            .close = close,
            .low = low,
            .high = high,
            .timestamp = timestamp,
            .volume = volume
        };

        try candles.append(gpa, candle);
    }

    var root: Root = try .init(
        gpa,
        .{
            .x = 20,
            .y = 20,
            .width = @as(f32, @floatFromInt(screen_width)),
            .height = @as(f32, @floatFromInt(screen_height)),
        },
        candles.items,
    );

    defer root.deinit(gpa);

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.{ .r = 10, .g = 10, .b = 15, .a = 255 });
        try root.handleEvents(gpa);
        root.draw(gpa);
        rl.drawFPS(10, 10);
    }
}

