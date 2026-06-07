const rl = @import("raylib");
const std = @import("std");

fn toScreen(value: f32, view_min: f32, view_max: f32, len: f32) f32 {
    const t = (value - view_min) / (view_max - view_min);
    return len * (1.0 - t);
}

fn toValue(screen: f32, view_min: f32, view_max: f32, len: f32) f32 {
    const t = 1.0 - (screen / len);
    return view_min + t * (view_max - view_min);
}

fn niceInterval(raw: f32) f32 {
    if (raw <= 0) return 1;
    const magnitude = std.math.pow(f32, 10.0, @floor(std.math.log10(raw)));
    const normalized = raw / magnitude;
    const nice: f32 = if (normalized < 1.5) 1.0 else if (normalized < 3.5) 2.0 else if (normalized < 7.5) 5.0 else 10.0;
    return nice * magnitude;
}

pub const Candle = struct {
    open: f32,
    close: f32,
    low: f32,
    high: f32,
    timestamp: u64,
};

pub const Timeframe = enum {
    d1,
    d5,
    m1,
    m3,
    y1,

    pub fn getMsDelta(self: Timeframe) f32 {
        return switch (self) {
            .d1 => 86_400_000.0,
            .d5 => 432_000_000.0,
            .m1 => 1_814_400_000.0,
            .m3 => 5_443_200_000.0,
            .y1 => 21_772_800_000.0,
        };
    }
};

const MinMax = struct {
    min: f32,
    max: f32,

    fn pad(self: *MinMax, factor: f32) void {
        const p = (self.max - self.min) * factor;
        self.max += p;
        self.min -= p;
    }
};

pub const CandleChart = struct {
    const Self = @This();
    const PRICE_FONT_SIZE: f32 = 14;
    const TARGET_GRID_LINES: f32 = 10;
    const Y_AXIS_WIDTH: f32 = 70;
    const X_AXIS_HEIGHT: f32 = 30;
    const CANDLE_SLOT: f32 = 20;
    const CANDLE_WIDTH: f32 = 18;
    const MIN_TICK_SPACING: f32 = 500.0;

    candles: []Candle,
    timeframe: Timeframe = .d1,
    screen_rect: rl.Rectangle,
    chart_screen_rect: rl.Rectangle,
    zoom_sensitivity: f32 = 0.1,

    view_x: MinMax,
    view_y: MinMax,

    candle_slot: f32 = CANDLE_SLOT,
    candle_width: f32 = CANDLE_WIDTH,
    pad: f32,

    font: rl.Font,

    drag_start_mouse: ?rl.Vector2 = null,
    drag_start_view_x: MinMax = .{ .min = 0, .max = 0 },
    drag_start_view_y: MinMax = .{ .min = 0, .max = 0 },

    pub fn init(screen_rect: rl.Rectangle, candles: []Candle, pad: f32) Self {
        const font = rl.loadFont("/Users/prateek/Library/Fonts/HackNerdFontMono-Bold.ttf") catch @panic("unable to load font");

        var chart_rect = screen_rect;
        chart_rect.width -= Y_AXIS_WIDTH;
        chart_rect.height -= X_AXIS_HEIGHT;

        var min_max = calcMinMax(candles);
        min_max.x.pad(pad);
        min_max.y.pad(pad);

        return .{
            .candles = candles,
            .screen_rect = screen_rect,
            .chart_screen_rect = chart_rect,
            .view_x = min_max.x,
            .view_y = min_max.y,
            .font = font,
            .pad = pad,
        };
    }

    fn calcMinMax(candles: []Candle) struct { y: MinMax, x: MinMax } {
        var y: MinMax = .{ .min = std.math.floatMax(f32), .max = std.math.floatMin(f32) };
        var x: MinMax = .{ .min = std.math.floatMax(f32), .max = std.math.floatMin(f32) };
        for (candles) |c| {
            const ts: f32 = @floatFromInt(c.timestamp);
            y.min = @min(y.min, c.low);
            y.max = @max(y.max, c.high);
            x.min = @min(x.min, ts);
            x.max = @max(x.max, ts);
        }
        return .{ .y = y, .x = x };
    }

    fn tsToScreenX(self: *const Self, ts: f32) f32 {
        const t = (ts - self.view_x.min) / (self.view_x.max - self.view_x.min);
        return self.chart_screen_rect.x + t * self.chart_screen_rect.width;
    }

    fn screenXToTs(self: *const Self, sx: f32) f32 {
        const t = (sx - self.chart_screen_rect.x) / self.chart_screen_rect.width;
        return self.view_x.min + t * (self.view_x.max - self.view_x.min);
    }

    fn drawGrid(self: *Self) void {
        const h = self.chart_screen_rect.height;
        const w = self.chart_screen_rect.width;
        const chart_top = self.chart_screen_rect.y;
        const axis_x = self.chart_screen_rect.x + w;

        const price_range = self.view_y.max - self.view_y.min;
        const raw_interval = price_range / TARGET_GRID_LINES;
        const interval = niceInterval(raw_interval);
        const first = @ceil(self.view_y.min / interval) * interval;

        var price = first;
        while (price <= self.view_y.max) : (price += interval) {
            const sy = toScreen(price, self.view_y.min, self.view_y.max, h);
            const screen_y = chart_top + sy;

            rl.drawLineEx(
                .{ .x = self.chart_screen_rect.x, .y = screen_y },
                .{ .x = axis_x, .y = screen_y },
                1.0,
                .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            );

            rl.drawLineEx(
                .{ .x = axis_x, .y = screen_y },
                .{ .x = axis_x + 4.0, .y = screen_y },
                1.0,
                .{ .r = 120, .g = 120, .b = 120, .a = 255 },
            );

            var buf: [16]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{price}) catch @panic("unable to convert float -> string");

            const label_x = axis_x + 8.0;
            const label_y = screen_y - PRICE_FONT_SIZE / 2.0;
            rl.drawTextEx(self.font, text, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, .white);
        }
    }

    fn drawXAxis(self: *Self) void {
        const chart_left = self.chart_screen_rect.x;
        const chart_right = self.chart_screen_rect.x + self.chart_screen_rect.width;
        const axis_y = self.chart_screen_rect.y + self.chart_screen_rect.height;
        const label_y = axis_y + 8.0;

        const ts_range = self.view_x.max - self.view_x.min;
        const ticks_that_fit = self.chart_screen_rect.width / MIN_TICK_SPACING;
        const raw_interval = ts_range / ticks_that_fit;
        const interval = niceInterval(raw_interval);

        const first_tick = @ceil(self.view_x.min / interval) * interval;
        var ts: f32 = first_tick;
        while (ts <= self.view_x.max) : (ts += interval) {
            const sx = self.tsToScreenX(ts);
            if (sx < chart_left or sx > chart_right) continue;

            rl.drawLineEx(
                .{ .x = sx, .y = self.chart_screen_rect.y },
                .{ .x = sx, .y = axis_y },
                1.0,
                .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            );

            rl.drawLineEx(
                .{ .x = sx, .y = axis_y },
                .{ .x = sx, .y = axis_y + 5.0 },
                1.0,
                .{ .r = 120, .g = 120, .b = 120, .a = 255 },
            );

            var buf: [24]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buf, "{d:.0}", .{ts}) catch continue;
            const text_size = rl.measureTextEx(self.font, text, PRICE_FONT_SIZE, 1);
            const label_x = sx - text_size.x / 2.0;
            rl.drawTextEx(self.font, text, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, .white);
        }
    }

    fn drawCandles(self: *Self) void {
        rl.beginScissorMode(
            @intFromFloat(self.chart_screen_rect.x),
            @intFromFloat(self.chart_screen_rect.y),
            @intFromFloat(self.chart_screen_rect.width),
            @intFromFloat(self.chart_screen_rect.height),
        );
        defer rl.endScissorMode();

        for (self.candles) |*c| {
            const ts: f32 = @floatFromInt(c.timestamp);
            const sx = self.tsToScreenX(ts) - self.candle_width / 2.0;

            if (sx + self.candle_width < self.chart_screen_rect.x) continue;
            if (sx > self.chart_screen_rect.x + self.chart_screen_rect.width) continue;

            self.drawCandleAt(c, sx);
        }
    }

    fn drawCandleAt(self: *Self, c: *const Candle, screen_x: f32) void {
        const w = self.candle_width;
        const h = self.chart_screen_rect.height;
        const top = self.chart_screen_rect.y;

        const open_y = top + toScreen(c.open, self.view_y.min, self.view_y.max, h);
        const close_y = top + toScreen(c.close, self.view_y.min, self.view_y.max, h);
        const high_y = top + toScreen(c.high, self.view_y.min, self.view_y.max, h);
        const low_y = top + toScreen(c.low, self.view_y.min, self.view_y.max, h);

        const body_top = @min(open_y, close_y);
        const body_height = @max(@abs(open_y - close_y), 1.0);
        const wick_x = screen_x + w / 2.0;

        const color = if (c.close >= c.open) rl.Color.green else rl.Color.red;

        rl.drawLineEx(.{ .x = wick_x, .y = high_y }, .{ .x = wick_x, .y = low_y }, 1.5, color);
        rl.drawRectangleV(.{ .x = screen_x, .y = body_top }, .{ .x = w, .y = body_height }, color);
    }

    pub fn draw(self: *Self) void {
        const axis_x = self.chart_screen_rect.x + self.chart_screen_rect.width;

        rl.drawRectangleRec(self.chart_screen_rect, .{ .r = 20, .g = 20, .b = 25, .a = 255 });

        const axis_bg: rl.Color = .{ .r = 30, .g = 20, .b = 30, .a = 255 };
        const axis_border_color: rl.Color = .{ .r = 160, .g = 60, .b = 160, .a = 255 };

        rl.drawRectangle(
            @intFromFloat(axis_x),
            @intFromFloat(self.screen_rect.y),
            @intFromFloat(Y_AXIS_WIDTH),
            @intFromFloat(self.chart_screen_rect.height),
            axis_bg,
        );

        rl.drawRectangle(
            @intFromFloat(self.chart_screen_rect.x),
            @intFromFloat(self.chart_screen_rect.y + self.chart_screen_rect.height),
            @intFromFloat(self.chart_screen_rect.width + Y_AXIS_WIDTH),
            @intFromFloat(X_AXIS_HEIGHT),
            axis_bg,
        );

        rl.drawLineEx(
            .{ .x = axis_x, .y = self.screen_rect.y },
            .{ .x = axis_x, .y = self.screen_rect.y + self.chart_screen_rect.height },
            1.0, axis_border_color,
        );

        rl.drawLineEx(
            .{ .x = self.chart_screen_rect.x, .y = self.chart_screen_rect.y + self.chart_screen_rect.height },
            .{ .x = axis_x, .y = self.chart_screen_rect.y + self.chart_screen_rect.height },
            1.0, axis_border_color,
        );

        self.drawGrid();
        self.drawXAxis();
        self.drawCandles();
    }

    pub fn scroll(
        self: *Self,
        wheel: f32,
        change_candle_slot: bool,
        change_time_axis: bool,
    ) void {
        const mid_x = (self.chart_screen_rect.x + self.chart_screen_rect.width) / 2 + self.chart_screen_rect.x;
        const cursor_ts = self.screenXToTs(mid_x);
        if (change_candle_slot) {
            const delta: f32 = if (wheel > 0) 2 else -2;
            const new_slot = self.candle_slot + delta;
            if (new_slot >= CANDLE_SLOT and new_slot <= 500.0) {
                const zoom_factor = self.candle_slot / new_slot;
                const new_min = cursor_ts + (self.view_x.min - cursor_ts) * zoom_factor;
                const new_max = cursor_ts + (self.view_x.max - cursor_ts) * zoom_factor;
                const diff = new_max - new_min;
                if (diff > 0.0001 and diff < 3_900_000_000) {
                    self.view_x.min = new_min;
                    self.view_x.max = new_max;
                    const ratio = self.candle_width / self.candle_width;
                    self.candle_slot = new_slot;
                    self.candle_width = new_slot * ratio;
                }
            }
        } else if (change_time_axis) {
            const factor: f32 = 1 + if (wheel > 0) -self.zoom_sensitivity else self.zoom_sensitivity;
            const new_min = cursor_ts + (self.view_x.min - cursor_ts) * factor;
            const new_max = cursor_ts + (self.view_x.max - cursor_ts) * factor;
            const diff = new_max - new_min;

            const ts_per_pixel = diff / self.chart_screen_rect.width;
            const time_per_candle_step: f32 = self.timeframe.getMsDelta(); 
            const projected_step_width_pixels = time_per_candle_step / ts_per_pixel;

            if (diff > 0.001 and diff < 3_900_000_000 and projected_step_width_pixels > self.candle_width) {
                const min_changed = @abs(self.view_x.min - new_min) > 0.01;
                const max_changed = @abs(self.view_x.max - new_max) > 0.01;

                if (!min_changed or !max_changed) {
                    const kick = time_per_candle_step * 0.1; 
                    self.view_x.min = new_min - kick;
                    self.view_x.max = new_max + kick;
                } else {
                    self.view_x.min = new_min;
                    self.view_x.max = new_max;
                }
            }
        } else {
            const cursor_price = (self.view_y.max - self.view_y.min) / 2 + self.view_y.min;
            const factor: f32 = 1 + if (wheel > 0) -self.zoom_sensitivity else self.zoom_sensitivity;
            const new_min = cursor_price + (self.view_y.min - cursor_price) * factor;
            const new_max = cursor_price + (self.view_y.max - cursor_price) * factor;
            const diff = new_max - new_min;
            if (diff > 0.001 and diff < 3_000_000_000) {
                self.view_y.min = new_min;
                self.view_y.max = new_max;
            }
        }
    }

    pub fn handleEvents(self: *Self) void {
        const mouse = rl.getMousePosition();
        const wheel = rl.getMouseWheelMove();

        if (wheel != 0) {
            self.scroll(wheel, rl.isKeyDown(.left_shift), rl.isKeyDown(.left_control));
        }

        if (rl.isMouseButtonPressed(.left)) {
            self.drag_start_mouse = mouse;
            self.drag_start_view_x = self.view_x;
            self.drag_start_view_y = self.view_y;
        }

        if (rl.isMouseButtonDown(.left)) {
            if (self.drag_start_mouse) |start| {
                const dx = mouse.x - start.x;
                const dy = mouse.y - start.y;

                const ts_per_pixel = (self.drag_start_view_x.max - self.drag_start_view_x.min) / self.chart_screen_rect.width;
                self.view_x.min = self.drag_start_view_x.min - dx * ts_per_pixel;
                self.view_x.max = self.drag_start_view_x.max - dx * ts_per_pixel;

                const price_per_pixel = (self.drag_start_view_y.max - self.drag_start_view_y.min) / self.chart_screen_rect.height;
                self.view_y.min = self.drag_start_view_y.min + dy * price_per_pixel;
                self.view_y.max = self.drag_start_view_y.max + dy * price_per_pixel;
            }
        }

        if (rl.isMouseButtonReleased(.left)) {
            self.drag_start_mouse = null;
        }

        if (rl.isKeyPressed(.r)) {
            var mm = calcMinMax(self.candles);
            mm.y.pad(self.pad);
            mm.x.pad(self.pad);
            self.view_y = mm.y;
            self.view_x = mm.x;
            self.candle_slot = CANDLE_SLOT;
            self.candle_width = CANDLE_WIDTH;
        }
    }
};
