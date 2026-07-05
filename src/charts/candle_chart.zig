const rl = @import("raylib");
const std = @import("std");
const common = @import("common");
const Timeframe = common.Timeframe;
const DateFormatter = common.DateFormatter;
const Layout = @import("layout");
const Resources = @import("resources");
const MinMax = common.MinMax;

pub const Candle = struct {
    open: f32,
    close: f32,
    low: f32,
    high: f32,
    timestamp: u64,
    volume: f32
};
const View = struct {
    x: MinMax = .{},
    y: MinMax = .{},
};
pub const MIN_TICK_SPACING: f32 = 300.0;
pub const TARGET_Y_AXIS_COUNT: f32 = 10;
pub const Y_AXIS_WIDTH: f32 = 70;
pub const X_AXIS_HEIGHT: f32 = 30;
pub const PRICE_FONT_SIZE: f32 = 14;
pub const CANDLE_SLOT: f32 = 20;
pub const CANDLE_WIDTH: f32 = 18;
pub const CHART_PAD = 0.05;
pub const CROSSHAIR_COLOR = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

pub const Self = @This();

candles: []Candle,
timeframe: Timeframe = .m1,
view: View = .{},
layout: Layout,

pub fn init(screen_rect: *const rl.Rectangle, candles: []Candle) Self {
    var r = screen_rect.*;
    r.height -= r.y * 2;
    r.width -= r.x * 2;

    r.width -= Y_AXIS_WIDTH;
    r.height -= X_AXIS_HEIGHT;

    var mm: View = calcMinMax(candles);

    mm.x.pad(CHART_PAD);
    mm.y.pad(CHART_PAD);

    return .{
        .candles = candles,
        .layout = .initRect(screen_rect, r),
        .view = mm
    };
}

pub fn calcMinMax(candles: []Candle) View {
    var y: common.MinMax = .{ .min = std.math.floatMax(f32), .max = std.math.floatMin(f32) };
    for (candles) |c| {
        y.min = @min(y.min, c.low);
        y.max = @max(y.max, c.high);
    }
    const last_index: f32 = if (candles.len == 0) 0 else @floatFromInt(candles.len - 1);
    const x: common.MinMax = .{ .min = 0, .max = last_index };
    return .{ .y = y, .x = x };
}

pub fn indexToScreenX(self: *const Self, index: f32) f32 {
    const range = self.view.x.range();
    const t = (index - self.view.x.min) / range;
    return self.layout.left + t * self.layout.width;
}

pub fn screenXToIndex(self: *const Self, sx: f32) f32 {
    const t = (sx - self.layout.left) / self.layout.width;
    return self.view.x.min + t * self.view.x.range();
}

pub fn viewToScreenY(self: *const Self, y: f32) f32 {
    const t = (y - self.view.y.min) / self.view.y.range();
    return (self.layout.height * (1.0 - t)) + self.layout.top;
}

pub fn screenToViewY(layout: *const Layout, view_y: *const MinMax, y: f32) f32 {
    const t = 1.0 - ((y - layout.top) / layout.height);
    return view_y.min + t * view_y.range();
}

pub fn tickStride(self: *const Self) f32 {
    const candles_per_pixel = self.view.x.range() / self.layout.width;
    const min_stride = candles_per_pixel * MIN_TICK_SPACING;
    return common.niceInterval(min_stride);
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

pub fn drawCandles(self: *Self) void {
    rl.beginScissorMode(
        @intFromFloat(self.layout.left),
        @intFromFloat(self.layout.top),
        @intFromFloat(self.layout.width),
        @intFromFloat(self.layout.height),
    );
    defer rl.endScissorMode();

    const slot_px = self.layout.width / self.view.x.range();
    const w = slot_px * 0.8;

    for (self.candles, 0..self.candles.len) |*c, i| {
        const idx: f32 = @floatFromInt(i);
        const sx = self.indexToScreenX(idx) - w / 2.0;

        if (sx + w < self.layout.left) continue;
        if (sx > self.layout.right()) continue;

        self.drawCandleAt(c, sx, w);
    }
}

pub fn drawCandleAt(self: *Self, c: *const Candle, screen_x: f32, w: f32) void {
    const open_y = self.viewToScreenY(c.open);
    const close_y = self.viewToScreenY(c.close);
    const high_y = self.viewToScreenY(c.high);
    const low_y = self.viewToScreenY(c.low);

    const body_top = @min(open_y, close_y);
    const body_height = @max(@abs(open_y - close_y), 1.0);
    const wick_x = screen_x + w / 2.0;

    const color = if (c.close >= c.open) rl.Color.green else rl.Color.red;

    rl.drawLineEx(.{ .x = wick_x, .y = high_y }, .{ .x = wick_x, .y = low_y }, 1.5, color);
    rl.drawRectangleV(.{ .x = screen_x, .y = body_top }, .{ .x = w, .y = body_height }, color);
}

pub fn drawCrosshair(
    self: *const Self,
    allocator: std.mem.Allocator,
    layout: *const Layout,
    view_y: *const MinMax,
    resources: *const Resources,
) !void {
    const mouse = rl.getMousePosition();

    rl.beginScissorMode(
        @intFromFloat(layout.screen_rect.x),
        @intFromFloat(layout.screen_rect.y),
        @intFromFloat(layout.width),
        @intFromFloat(layout.screen_rect.height),
    ); {
        const dash_size = 3;
        const space_size = 3;
        rl.drawLineDashed(
            .{ .x = layout.left, .y = mouse.y },
            .{ .x = layout.right(), .y = mouse.y },
            dash_size, space_size, CROSSHAIR_COLOR
        );

        rl.drawLineDashed(
            .{ .x = mouse.x, .y = layout.screen_rect.y },
            .{ .x = mouse.x, .y = layout.screen_rect.height },
            dash_size, space_size, CROSSHAIR_COLOR
        );
    } rl.endScissorMode();

    var buf: [24]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{screenToViewY(layout, view_y, mouse.y)}) catch @panic("unable to convert float -> string");

    var label_x = layout.right() + 8.0;
    var label_y = mouse.y - PRICE_FONT_SIZE / 2.0;
    const pad = 4;
    
    rl.drawRectangleV(
        .{ .x = layout.right(), .y = label_y - pad },
        .{ .x = Y_AXIS_WIDTH, .y = PRICE_FONT_SIZE + (pad * 2) },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 }
    );

    rl.drawTextEx(resources.font, text, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, .black);

    buf = undefined;
    
    const ts = self.indexToTs(self.screenXToIndex(mouse.x));
    const epoch_seconds = @divFloor(ts, 1000);
    const shows_time = self.timeframe.showsTime();

    label_y = layout.screen_rect.height - (layout.screen_rect.y / 2) + 8.0;

    const time_text = try (
        if (shows_time)
            DateFormatter.toTextualTime(allocator, epoch_seconds)
        else
            DateFormatter.toTextual(allocator, epoch_seconds)
    );
    defer allocator.free(time_text);

    const text_size = rl.measureTextEx(resources.font, time_text, PRICE_FONT_SIZE, 1);
    label_x = mouse.x - text_size.x / 2.0;

    rl.drawRectangleV(
        .{ .x = label_x - pad, .y = label_y - pad },
        .{ .x = text_size.x + (pad * 2), .y = PRICE_FONT_SIZE + (pad * 2) },
        .{ .r = 255, .g = 255, .b = 255, .a = 255 }
    );

    rl.drawTextEx(resources.font, time_text, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, .black);
}

pub fn drawYAxis(self: *Self, resources: *const Resources) void {
    const r = self.layout.right();
    const price_range = self.view.y.range();
    const raw_interval = price_range / TARGET_Y_AXIS_COUNT;
    const interval = common.niceInterval(raw_interval);
    const first = @ceil(self.view.y.min / interval) * interval;

    rl.drawRectangle(
        @intFromFloat(r),
        @intFromFloat(self.layout.top),
        @intFromFloat(Y_AXIS_WIDTH),
        @intFromFloat(self.layout.height),
        Resources.AXIS_BG,
    );

    rl.drawLineEx(
        .{ .x = r, .y = self.layout.top },
        .{ .x = r, .y = self.layout.top + self.layout.height },
        1.0, Resources.AXIS_BORDER_COLOR,
    );

    var price = first;
    while (price <= self.view.y.max) : (price += interval) {
        const sy = self.viewToScreenY(price);
        const screen_y = sy;

        rl.drawLineEx(
            .{ .x = self.layout.left, .y = screen_y },
            .{ .x = r, .y = screen_y },
            1.0,
            Resources.GRID_COLOR
        );

        rl.drawLineEx(
            .{ .x = r, .y = screen_y },
            .{ .x = r + 4.0, .y = screen_y },
            1.0,
            .{ .r = 120, .g = 120, .b = 120, .a = 255 },
        );

        var buf: [16]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{price}) catch @panic("unable to convert float -> string");

        const label_x = r + 8.0;
        const label_y = screen_y - PRICE_FONT_SIZE / 2.0;
        rl.drawTextEx(resources.font, text, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, .white);
    }
}

pub fn drawXAxis(self: *Self, allocator: std.mem.Allocator, resources: *Resources) !void {
    const axis_y = self.layout.screen_rect.height - (self.layout.top / 2);
    const label_y = axis_y + 8.0;

    const stride = self.tickStride();
    const first_tick = @ceil(self.view.x.min / stride) * stride;
    const shows_time = self.timeframe.showsTime();

    rl.drawRectangle(
        @intFromFloat(self.layout.left),
        @intFromFloat(axis_y),
        @intFromFloat(self.layout.width + Y_AXIS_WIDTH),
        @intFromFloat(X_AXIS_HEIGHT),
        Resources.AXIS_BG,
    );

    var index: f32 = first_tick;
    while (index <= self.view.x.max) : (index += stride) {
        const sx = self.indexToScreenX(index);
        if (sx < self.layout.left or sx > self.layout.right()) continue;

        rl.drawLineEx(
            .{ .x = sx, .y = self.layout.top },
            .{ .x = sx, .y = axis_y },
            1.0,
            Resources.GRID_COLOR
        );

        rl.drawLineEx(
            .{ .x = sx, .y = axis_y },
            .{ .x = sx, .y = axis_y + 5.0 },
            1.0,
            .{ .r = 120, .g = 120, .b = 120, .a = 255 },
        );

        const ts = self.indexToTs(index);
        const epoch_seconds = @divFloor(ts, 1000);

        const text = try (
            if (shows_time)
                DateFormatter.toTextualTime(allocator, epoch_seconds)
            else
                DateFormatter.toTextual(allocator, epoch_seconds)
        );
        defer allocator.free(text);

        const text_size = rl.measureTextEx(resources.font, text, PRICE_FONT_SIZE, 1);
        const label_x = sx - text_size.x / 2.0;
        rl.drawTextEx(resources.font, text, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, .white);
    }
}
