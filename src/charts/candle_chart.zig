const rl = @import("raylib");
const std = @import("std");
const common = @import("common");
const Timeframe = common.Timeframe;
const DateFormatter = common.DateFormatter;
const Layout = @import("layout");

pub const Candle = struct {
    open: f32,
    close: f32,
    low: f32,
    high: f32,
    timestamp: u64,
    volume: f32
};

pub const Self = @This();

candles: []Candle,
timeframe: Timeframe = .m1,

pub fn calcMinMax(self: *const Self) common.MinMaxYX {
    var y: common.MinMax = .{ .min = std.math.floatMax(f32), .max = std.math.floatMin(f32) };
    for (self.candles) |c| {
        y.min = @min(y.min, c.low);
        y.max = @max(y.max, c.high);
    }
    const last_index: f32 = if (self.candles.len == 0) 0 else @floatFromInt(self.candles.len - 1);
    const x: common.MinMax = .{ .min = 0, .max = last_index };
    return .{ .y = y, .x = x };
}

pub fn indexToTs(self: *const Self, index: f32) i64 {
    if (self.candles.len == 0) return 0;
    const ms_per_candle = self.timeframe.getMsDelta();
    const base_index: usize = @intFromFloat(@max(0, @min(index, @as(f32, @floatFromInt(self.candles.len - 1)))));
    const base_ts: i64 = @intCast(self.candles[base_index].timestamp);
    const frac = index - @as(f32, @floatFromInt(base_index));
    const delta_ms: i64 = @intFromFloat(frac * ms_per_candle);
    return base_ts + delta_ms;
}

pub fn drawCandles(self: *Self, layout: *const Layout) void {
    rl.beginScissorMode(
        @intFromFloat(layout.chartLeft()),
        @intFromFloat(layout.chartTop()),
        @intFromFloat(layout.chart_screen_rect.width),
        @intFromFloat(layout.chart_screen_rect.height),
    );
    defer rl.endScissorMode();

    const index_range = layout.view_x.max - layout.view_x.min;
    const slot_px = layout.chart_screen_rect.width / index_range;
    const w = slot_px * 0.8;

    for (self.candles, 0..self.candles.len) |*c, i| {
        const idx: f32 = @floatFromInt(i);
        const sx = layout.indexToScreenX(idx) - w / 2.0;

        if (sx + w < layout.chartLeft()) continue;
        if (sx > layout.chartRight()) continue;

        drawCandleAt(layout, c, sx, w);
    }
}

pub fn drawCandleAt(layout: *const Layout, c: *const Candle, screen_x: f32, w: f32) void {
    const top = layout.chartTop();

    const open_y = top + layout.priceToScreenY(c.open);
    const close_y = top + layout.priceToScreenY(c.close);
    const high_y = top + layout.priceToScreenY(c.high);
    const low_y = top + layout.priceToScreenY(c.low);

    const body_top = @min(open_y, close_y);
    const body_height = @max(@abs(open_y - close_y), 1.0);
    const wick_x = screen_x + w / 2.0;

    const color = if (c.close >= c.open) rl.Color.green else rl.Color.red;

    rl.drawLineEx(.{ .x = wick_x, .y = high_y }, .{ .x = wick_x, .y = low_y }, 1.5, color);
    rl.drawRectangleV(.{ .x = screen_x, .y = body_top }, .{ .x = w, .y = body_height }, color);
}

pub fn drawCrosshair(self: *const Self, layout: *const Layout, date_formatter: *common.DateFormatter) void {
    const mouse = rl.getMousePosition();

    rl.beginScissorMode(
        @intFromFloat(layout.chartLeft()),
        @intFromFloat(layout.chartTop()),
        @intFromFloat(layout.chart_screen_rect.width),
        @intFromFloat(layout.chart_screen_rect.height),
    ); {
        const crosshair_color = rl.Color{ .r = 230, .g = 0, .b = 180, .a = 255 };
        const dash_size = 3;
        const space_size = 3;
        rl.drawLineDashed(
            .{ .x = layout.chartLeft(), .y = mouse.y },
            .{ .x = layout.chartRight(), .y = mouse.y },
            dash_size, space_size, crosshair_color
        );

        rl.drawLineDashed(
            .{ .x = mouse.x, .y = layout.chartTop() },
            .{ .x = mouse.x, .y = layout.chartBottom() },
            dash_size, space_size, crosshair_color
        );
    } rl.endScissorMode();

    var buf: [24]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{layout.screenYToPrice(mouse.y)}) catch @panic("unable to convert float -> string");

    var label_x = layout.chartRight() + 8.0;
    var label_y = mouse.y - Layout.PRICE_FONT_SIZE / 2.0;
    const pad = 4;
    
    rl.drawRectangleV(
        .{ .x = layout.chartRight(), .y = label_y - pad },
        .{ .x = Layout.Y_AXIS_WIDTH, .y = Layout.PRICE_FONT_SIZE + (pad * 2) },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 }
    );

    rl.drawTextEx(layout.font, text, .{ .x = label_x, .y = label_y }, Layout.PRICE_FONT_SIZE, 1, .black);

    buf = undefined;
    
    const ts = self.indexToTs(layout.screenXToIndex(mouse.x));
    const epoch_seconds = @divFloor(ts, 1000);
    const shows_time = self.timeframe.showsTime();

    label_y = layout.chartBottom() + 8.0;

    const time_text = (
        if (shows_time)
            date_formatter.toTextualTime(epoch_seconds)
        else
            date_formatter.toTextual(epoch_seconds)
    ) catch @panic("error in formating timestamp");
    defer date_formatter.allocator.free(time_text);

    const textZ = std.fmt.bufPrintZ(&buf, "{s}", .{time_text}) catch @panic("error in formating timestamp");
    const text_size = rl.measureTextEx(layout.font, textZ, Layout.PRICE_FONT_SIZE, 1);
    label_x = mouse.x - text_size.x / 2.0;

    rl.drawRectangleV(
        .{ .x = label_x - pad, .y = label_y - pad },
        .{ .x = text_size.x + (pad * 2), .y = Layout.PRICE_FONT_SIZE + (pad * 2) },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 }
    );

    rl.drawTextEx(layout.font, textZ, .{ .x = label_x, .y = label_y }, Layout.PRICE_FONT_SIZE, 1, .black);
}

