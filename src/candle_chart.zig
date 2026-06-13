const rl = @import("raylib");
const std = @import("std");

fn niceInterval(raw: f32) f32 {
    if (raw <= 0) return 1;
    const magnitude = std.math.pow(f32, 10.0, @floor(std.math.log10(raw)));
    const normalized = raw / magnitude;
    const nice: f32 = if (normalized < 1.5) 1.0 else if (normalized < 3.5) 2.0 else if (normalized < 7.5) 5.0 else 10.0;
    return nice * magnitude;
}

const MonthNames = [_][]const u8{
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

pub const DateFormatter = struct {
    allocator: std.mem.Allocator,

    pub fn toNumericDash(self: *const DateFormatter, epoch_seconds: i64) ![]u8 {
        const epoch_days = @divFloor(epoch_seconds, std.time.epoch.secs_per_day);
        const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_days) };
        const year_and_day = epoch_day.calculateYearDay()();
        const month_and_day = year_and_day.calculateMonthAndDay();

        return try std.fmt.allocPrint(self.allocator, "{d:0>2}-{d:0>2}-{d:0>4}", .{
            month_and_day.day_index + 1,
            month_and_day.month.numeric(),
            year_and_day.year,
        });
    }

    pub fn toTextual(self: *const DateFormatter, epoch_seconds: i64) ![]u8 {
        const epoch_days = @divFloor(epoch_seconds, std.time.epoch.secs_per_day);
        const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_days) };
        const year_and_day = epoch_day.calculateYearDay();
        const month_and_day = year_and_day.calculateMonthDay();

        const month_idx = month_and_day.month.numeric() - 1;

        return try std.fmt.allocPrint(self.allocator, "{s} {d}, {d}", .{
            MonthNames[month_idx],
            month_and_day.day_index + 1,
            year_and_day.year,
        });
    }

    pub fn toTextualTime(self: *const DateFormatter, epoch_seconds: i64) ![]u8 {
        const secs_per_day: i64 = std.time.epoch.secs_per_day;
        const epoch_days = @divFloor(epoch_seconds, secs_per_day);
        const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_days) };
        const year_and_day = epoch_day.calculateYearDay();
        const month_and_day = year_and_day.calculateMonthDay();
        const month_idx = month_and_day.month.numeric() - 1;

        var secs_of_day = @mod(epoch_seconds, secs_per_day);
        if (secs_of_day < 0) secs_of_day += secs_per_day;

        const hours: u64 = @intCast(@divFloor(secs_of_day, 3600));
        const minutes: u64 = @intCast(@divFloor(@mod(secs_of_day, 3600), 60));

        return try std.fmt.allocPrint(self.allocator, "{s} {d} {d:0>2}:{d:0>2}", .{
            MonthNames[month_idx],
            month_and_day.day_index + 1,
            hours,
            minutes,
        });
    }
};

pub const Candle = struct {
    open: f32,
    close: f32,
    low: f32,
    high: f32,
    timestamp: u64,
    volume: f32
};

pub const Timeframe = enum {
    m1,
    m5,
    m30,
    h1,
    d1,
    d7,

    pub fn getMsDelta(self: Timeframe) f32 {
        return switch (self) {
            .m1 => 60_000.0,
            .m5 => 300_000.0,
            .m30 => 1_800_000.0,
            .h1 => 3_600_000.0,
            .d1 => 86_400_000.0,
            .d7 => 604_800_000.0,
        };
    }

    fn showsTime(self: Timeframe) bool {
        return switch (self) {
            .m1, .m5, .m30, .h1 => true,
            .d1, .d7 => false,
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

    inline fn range(self: *const MinMax) f32 {
        return self.max - self.min;
    }
};

pub const CandleChart = struct {
    const Self = @This();
    const PRICE_FONT_SIZE: f32 = 14;
    const TARGET_Y_AXIS_COUNT: f32 = 10;
    const Y_AXIS_WIDTH: f32 = 70;
    const X_AXIS_HEIGHT: f32 = 30;
    const CANDLE_SLOT: f32 = 20;
    const CANDLE_WIDTH: f32 = 18;
    const MIN_TICK_SPACING: f32 = 300.0;

    candles: []Candle,
    timeframe: Timeframe = .m1,
    screen_rect: rl.Rectangle,
    chart_screen_rect: rl.Rectangle,
    zoom_sensitivity: f32 = 0.05,

    view_x: MinMax,
    view_y: MinMax,

    candle_slot: f32 = CANDLE_SLOT,
    candle_width: f32 = CANDLE_WIDTH,
    pad: f32,

    font: rl.Font,

    drag_start_mouse: ?rl.Vector2 = null,
    drag_start_view_x: MinMax = .{ .min = 0, .max = 0 },
    drag_start_view_y: MinMax = .{ .min = 0, .max = 0 },
    date_formatter: DateFormatter,

    pub fn init(allocator: std.mem.Allocator, screen_rect: rl.Rectangle, candles: []Candle, pad: f32) Self {
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
            .date_formatter = DateFormatter{ .allocator = allocator }
        };
    }

    fn calcMinMax(candles: []Candle) struct { y: MinMax, x: MinMax } {
        var y: MinMax = .{ .min = std.math.floatMax(f32), .max = std.math.floatMin(f32) };
        for (candles) |c| {
            y.min = @min(y.min, c.low);
            y.max = @max(y.max, c.high);
        }
        const last_index: f32 = if (candles.len == 0) 0 else @floatFromInt(candles.len - 1);
        const x: MinMax = .{ .min = 0, .max = last_index };
        return .{ .y = y, .x = x };
    }

    fn indexToTs(self: *const Self, index: f32) i64 {
        if (self.candles.len == 0) return 0;
        const ms_per_candle = self.timeframe.getMsDelta();
        const base_index: usize = @intFromFloat(@max(0, @min(index, @as(f32, @floatFromInt(self.candles.len - 1)))));
        const base_ts: i64 = @intCast(self.candles[base_index].timestamp);
        const frac = index - @as(f32, @floatFromInt(base_index));
        const delta_ms: i64 = @intFromFloat(frac * ms_per_candle);
        return base_ts + delta_ms;
    }

    fn indexToScreenX(self: *const Self, index: f32) f32 {
        const range = self.view_x.range();
        const t = (index - self.view_x.min) / range;
        return self.chart_screen_rect.x + t * self.chart_screen_rect.width;
    }

    fn screenXToIndex(self: *const Self, sx: f32) f32 {
        const t = (sx - self.chart_screen_rect.x) / self.chart_screen_rect.width;
        return self.view_x.min + t * self.view_x.range();
    }

    fn priceToScreenY(self: *const Self, price: f32) f32 {
        const t = (price - self.view_y.min) / self.view_y.range();
        return self.chart_screen_rect.height * (1.0 - t);
    }

    fn screenYToPrice(self: *const Self, y: f32) f32 {
        const t = 1.0 - ((y - self.chart_screen_rect.y) / self.chart_screen_rect.height);
        return self.view_y.min + t * self.view_y.range();
    }

    fn tickStride(self: *const Self) f32 {
        const index_range = self.view_x.max - self.view_x.min;
        const candles_per_pixel = index_range / self.chart_screen_rect.width;
        const min_stride = candles_per_pixel * MIN_TICK_SPACING;
        return niceInterval(min_stride);
    }

    fn drawYAxis(self: *Self) void {
        const chart_top = self.chart_screen_rect.y;
        const right = self.chartRight();

        const price_range = self.view_y.max - self.view_y.min;
        const raw_interval = price_range / TARGET_Y_AXIS_COUNT;
        const interval = niceInterval(raw_interval);
        const first = @ceil(self.view_y.min / interval) * interval;

        var price = first;
        while (price <= self.view_y.max) : (price += interval) {
            const sy = self.priceToScreenY(price);
            const screen_y = chart_top + sy;

            rl.drawLineEx(
                .{ .x = self.chart_screen_rect.x, .y = screen_y },
                .{ .x = right, .y = screen_y },
                1.0,
                .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            );

            rl.drawLineEx(
                .{ .x = right, .y = screen_y },
                .{ .x = right + 4.0, .y = screen_y },
                1.0,
                .{ .r = 120, .g = 120, .b = 120, .a = 255 },
            );

            var buf: [16]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{price}) catch @panic("unable to convert float -> string");

            const label_x = right + 8.0;
            const label_y = screen_y - PRICE_FONT_SIZE / 2.0;
            rl.drawTextEx(self.font, text, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, .white);
        }
    }

    inline fn chartLeft(self: *const Self) f32 {
        return self.chart_screen_rect.x;
    }

    inline fn chartRight(self: *const Self) f32 {
        return self.chart_screen_rect.x + self.chart_screen_rect.width;
    }

    inline fn chartBottom(self: *const Self) f32 {
        return self.chart_screen_rect.y + self.chart_screen_rect.height;
    }

    fn drawXAxis(self: *Self) void {
        const axis_y = self.chart_screen_rect.y + self.chart_screen_rect.height;
        const label_y = axis_y + 8.0;

        const stride = self.tickStride();
        const first_tick = @ceil(self.view_x.min / stride) * stride;
        const shows_time = self.timeframe.showsTime();

        var index: f32 = first_tick;
        while (index <= self.view_x.max) : (index += stride) {
            const sx = self.indexToScreenX(index);
            if (sx < self.chartLeft() or sx > self.chartRight()) continue;

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

            const ts = self.indexToTs(index);
            const epoch_seconds = @divFloor(ts, 1000);

            var buf: [24]u8 = undefined;
            const text = (
                if (shows_time)
                    self.date_formatter.toTextualTime(epoch_seconds)
                else
                    self.date_formatter.toTextual(epoch_seconds)
            ) catch continue;

            defer self.date_formatter.allocator.free(text);
            const textZ = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch continue;
            const text_size = rl.measureTextEx(self.font, textZ, PRICE_FONT_SIZE, 1);
            const label_x = sx - text_size.x / 2.0;
            rl.drawTextEx(self.font, textZ, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, .white);
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

        const index_range = self.view_x.max - self.view_x.min;
        const slot_px = self.chart_screen_rect.width / index_range;
        // const w = @min(self.candle_width, slot_px * 0.8);
        const w = slot_px * 0.8;

        for (self.candles, 0..self.candles.len) |*c, i| {
            const idx: f32 = @floatFromInt(i);
            const sx = self.indexToScreenX(idx) - w / 2.0;

            if (sx + w < self.chart_screen_rect.x) continue;
            if (sx > self.chart_screen_rect.x + self.chart_screen_rect.width) continue;

            self.drawCandleAt(c, sx, w);
        }
    }

    fn drawCandleAt(self: *Self, c: *const Candle, screen_x: f32, w: f32) void {
        const top = self.chart_screen_rect.y;

        const open_y = top + self.priceToScreenY(c.open);
        const close_y = top + self.priceToScreenY(c.close);
        const high_y = top + self.priceToScreenY(c.high);
        const low_y = top + self.priceToScreenY(c.low);

        const body_top = @min(open_y, close_y);
        const body_height = @max(@abs(open_y - close_y), 1.0);
        const wick_x = screen_x + w / 2.0;

        const color = if (c.close >= c.open) rl.Color.green else rl.Color.red;

        rl.drawLineEx(.{ .x = wick_x, .y = high_y }, .{ .x = wick_x, .y = low_y }, 1.5, color);
        rl.drawRectangleV(.{ .x = screen_x, .y = body_top }, .{ .x = w, .y = body_height }, color);
    }

    fn drawCrosshair(self: *Self) void {
        const mouse = rl.getMousePosition();
        const crosshair_color = rl.Color{ .r = 230, .g = 0, .b = 180, .a = 255 };
        const dash_size = 3;
        const space_size = 3;
        rl.drawLineDashed(
            .{ .x = self.chart_screen_rect.x, .y = mouse.y },
            .{ .x = self.chartRight(), .y = mouse.y },
            dash_size, space_size, crosshair_color
        );

        rl.drawLineDashed(
            .{ .x = mouse.x, .y = self.chart_screen_rect.y },
            .{ .x = mouse.x, .y = self.chartBottom() },
            dash_size, space_size, crosshair_color
        );

        var buf: [16]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{self.screenYToPrice(mouse.y)}) catch @panic("unable to convert float -> string");

        const label_x = self.chartRight() + 8.0;
        const label_y = mouse.y - PRICE_FONT_SIZE / 2.0;
        const pad = 4;
        
        rl.drawRectangleV(
            .{ .x = self.chartRight(), .y = label_y - pad },
            .{ .x = Y_AXIS_WIDTH, .y = PRICE_FONT_SIZE + (pad * 2) },
            .{ .r = 0, .g = 0, .b = 0, .a = 255 }
        );

        rl.drawTextEx(self.font, text, .{ .x = label_x, .y = label_y }, PRICE_FONT_SIZE, 1, crosshair_color);
    }

    pub fn draw(self: *Self) void {
        const right = self.chartRight();

        rl.drawRectangleRec(self.chart_screen_rect, .{ .r = 20, .g = 20, .b = 25, .a = 255 });

        const axis_bg: rl.Color = .{ .r = 30, .g = 20, .b = 30, .a = 255 };
        const axis_border_color: rl.Color = .{ .r = 160, .g = 60, .b = 160, .a = 255 };

        rl.drawRectangle(
            @intFromFloat(right),
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
            .{ .x = right, .y = self.screen_rect.y },
            .{ .x = right, .y = self.screen_rect.y + self.chart_screen_rect.height },
            1.0, axis_border_color,
        );

        rl.drawLineEx(
            .{ .x = self.chart_screen_rect.x, .y = self.chart_screen_rect.y + self.chart_screen_rect.height },
            .{ .x = right, .y = self.chart_screen_rect.y + self.chart_screen_rect.height },
            1.0, axis_border_color,
        );

        self.drawYAxis();
        self.drawXAxis();
        self.drawCandles();
        self.drawCrosshair();
    }

    pub fn scroll(
        self: *Self,
        wheel: f32,
        change_candle_slot: bool,
        change_time_axis: bool,
    ) void {
        const mid_x = self.chart_screen_rect.x + self.chart_screen_rect.width / 2;
        const cursor_index = self.screenXToIndex(mid_x);
        if (change_candle_slot or change_time_axis) {
            const factor: f32 = 1 + if (wheel > 0) -self.zoom_sensitivity else self.zoom_sensitivity;
            const new_min = cursor_index + (self.view_x.min - cursor_index) * factor;
            const new_max = cursor_index + (self.view_x.max - cursor_index) * factor;
            const diff = new_max - new_min;

            const max_candles_in_view: f32 = @floatFromInt(self.candles.len * 2 + 64);
            if (diff > 4 and diff < max_candles_in_view) {
                self.view_x.min = new_min;
                self.view_x.max = new_max;
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
        if(rl.isWindowResized()) {
            self.screen_rect.height = @floatFromInt(rl.getScreenHeight());
            self.screen_rect.width = @floatFromInt(rl.getScreenWidth());

            self.chart_screen_rect.height = self.screen_rect.height;
            self.chart_screen_rect.width = self.screen_rect.width;

            self.chart_screen_rect.width -= Y_AXIS_WIDTH;
            self.chart_screen_rect.height -= X_AXIS_HEIGHT;
        }

        const mouse = rl.getMousePosition();
        const wheel = rl.getMouseWheelMoveV();

        const wdx = wheel.x * self.zoom_sensitivity;
        const wdy = wheel.y * self.zoom_sensitivity;

        const deadzone = 0.01;

        if (@abs(wdx) > deadzone or @abs(wdy) > deadzone) {
            if (@abs(wdx) > @abs(wdy)) {
                const scroll_x_multiplier = self.view_x.range() / 10;
                self.view_x.min -= wdx * scroll_x_multiplier;
                self.view_x.max -= wdx * scroll_x_multiplier;
            } else {
                self.scroll(wdy, rl.isKeyDown(.left_shift), rl.isKeyDown(.left_control));
            }
        }

        if (rl.isMouseButtonDown(.left)) {
            if (self.drag_start_mouse) |start| {
                const dx = mouse.x - start.x;
                const dy = mouse.y - start.y;

                const index_per_pixel = (self.drag_start_view_x.max - self.drag_start_view_x.min) / self.chart_screen_rect.width;
                self.view_x.min = self.drag_start_view_x.min - dx * index_per_pixel;
                self.view_x.max = self.drag_start_view_x.max - dx * index_per_pixel;

                const price_per_pixel = (self.drag_start_view_y.max - self.drag_start_view_y.min) / self.chart_screen_rect.height;
                self.view_y.min = self.drag_start_view_y.min + dy * price_per_pixel;
                self.view_y.max = self.drag_start_view_y.max + dy * price_per_pixel;
            } else {
                self.drag_start_mouse = mouse;
                self.drag_start_view_x = self.view_x;
                self.drag_start_view_y = self.view_y;
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
