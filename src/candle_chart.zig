const rl = @import("raylib");
const std = @import("std");

fn toScreenY(price: f32, view_min: f32, view_max: f32, chart_height: f32) f32 {
    const t = (price - view_min) / (view_max - view_min);
    return chart_height * (1.0 - t);
}

fn toPriceY(screen_y: f32, view_min: f32, view_max: f32, chart_height: f32) f32 {
    const t = 1.0 - (screen_y / chart_height);
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

pub const CandleChart = struct {
    const Self = @This();
    const PRICE_FONT_SIZE: f32 = 14;
    const TARGET_GRID_LINES: f32 = 8;
    const CANDLE_GAP_RATIO: f32 = 0;
    const Y_AXIS_WIDTH: f32 = 70;
    const CANDLE_SLOT: f32 = 18;
    const CANDLE_WIDTH: f32 = 16;

    candles: []Candle,
    screen_rect: rl.Rectangle,
    chart_screen_rect: rl.Rectangle,

    view_min: f32,
    view_max: f32,

    x_offset: f32 = 0,
    candle_slot: f32 = CANDLE_SLOT,
    candle_width: f32 = CANDLE_WIDTH,

    font: rl.Font,

    drag_start_mouse: ?rl.Vector2 = null,
    drag_start_x_offset: f32 = 0,
    drag_start_view_min: f32 = 0,
    drag_start_view_max: f32 = 0,

    pub fn init(screen_rect: rl.Rectangle, candles: []Candle) Self {
        const font = rl.loadFont("/Users/prateek/Library/Fonts/HackNerdFontMono-Bold.ttf") catch @panic("unable to load font");

        var chart_rect = screen_rect;
        chart_rect.width -= Y_AXIS_WIDTH;

        const min_max = calcMinMax(candles);
        const pad = (min_max.@"1" - min_max.@"0") * 0.05;

        return .{
            .candles = candles,
            .screen_rect = screen_rect,
            .chart_screen_rect = chart_rect,
            .view_min = min_max.@"0" - pad,
            .view_max = min_max.@"1" + pad,
            .font = font,
        };
    }

    fn calcMinMax(candles: []Candle) struct { f32, f32 } {
        var min = std.math.floatMax(f32);
        var max = std.math.floatMin(f32);
        for (candles) |c| {
            min = @min(min, c.low);
            max = @max(max, c.high);
        }
        return .{ min, max };
    }

    fn candleScreenX(self: *const Self, idx: usize) f32 {
        const n = @as(f32, @floatFromInt(self.candles.len));
        const i = @as(f32, @floatFromInt(idx));
        const slot_from_right = (n - 1.0 - i) + self.x_offset;
        return self.chart_screen_rect.x + self.chart_screen_rect.width - (slot_from_right + 1.0) * self.candle_slot;
    }

    fn drawGrid(self: *Self) void {
        const h = self.chart_screen_rect.height;
        const w = self.chart_screen_rect.width;
        const chart_top = self.chart_screen_rect.y;
        const axis_x = self.chart_screen_rect.x + w;

        const price_range = self.view_max - self.view_min;
        const raw_interval = price_range / TARGET_GRID_LINES;
        const interval = niceInterval(raw_interval);
        const first = @ceil(self.view_min / interval) * interval;

        var price = first;
        while (price <= self.view_max) : (price += interval) {
            const sy = toScreenY(price, self.view_min, self.view_max, h);
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

    fn drawCandles(self: *Self) void {
        rl.beginScissorMode(
            @intFromFloat(self.chart_screen_rect.x),
            @intFromFloat(self.chart_screen_rect.y),
            @intFromFloat(self.chart_screen_rect.width),
            @intFromFloat(self.chart_screen_rect.height),
        );
        defer rl.endScissorMode();

        for (self.candles, 0..) |*c, i| {
            const sx = self.candleScreenX(i);

            if (sx + self.candle_width < self.chart_screen_rect.x) continue;
            if (sx > self.chart_screen_rect.x + self.chart_screen_rect.width) continue;

            const translated_x = sx;

            self.drawCandleAt(c, translated_x);
        }
    }

    fn drawCandleAt(self: *Self, c: *const Candle, screen_x: f32) void {
        const w = self.candle_width;
        const h = self.chart_screen_rect.height;
        const top = self.chart_screen_rect.y;

        const open_y = top + toScreenY(c.open, self.view_min, self.view_max, h);
        const close_y = top + toScreenY(c.close, self.view_min, self.view_max, h);
        const high_y = top + toScreenY(c.high, self.view_min, self.view_max, h);
        const low_y = top + toScreenY(c.low, self.view_min, self.view_max, h);

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

        rl.drawRectangle(
            @intFromFloat(axis_x),
            @intFromFloat(self.screen_rect.y),
            @intFromFloat(Y_AXIS_WIDTH),
            @intFromFloat(self.screen_rect.height),
            .{ .r = 15, .g = 15, .b = 20, .a = 255 },
        );
        rl.drawLineEx(
            .{ .x = axis_x, .y = self.screen_rect.y },
            .{ .x = axis_x, .y = self.screen_rect.y + self.screen_rect.height },
            1.0,
            .{ .r = 60, .g = 60, .b = 60, .a = 255 },
        );

        self.drawGrid();
        self.drawCandles();
    }

    pub fn handleEvents(self: *Self) void {
        const mouse = rl.getMousePosition();

        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            const cursor_price = toPriceY(
                mouse.y - self.chart_screen_rect.y,
                self.view_min,
                self.view_max,
                self.chart_screen_rect.height,
            );
            const factor: f32 = if (wheel > 0) 0.90 else 1.1;
            const new_min = cursor_price + (self.view_min - cursor_price) * factor;
            const new_max = cursor_price + (self.view_max - cursor_price) * factor;
            if (new_max - new_min > 0.001) {
                self.view_min = new_min;
                self.view_max = new_max;
            }
        }

        if (rl.isMouseButtonPressed(.left)) {
            self.drag_start_mouse = mouse;
            self.drag_start_x_offset = self.x_offset;
            self.drag_start_view_min = self.view_min;
            self.drag_start_view_max = self.view_max;
        }

        if (rl.isMouseButtonDown(.left)) {
            if (self.drag_start_mouse) |start| {
                const dx = mouse.x - start.x;
                const dy = mouse.y - start.y;
                const price_range = self.drag_start_view_max - self.drag_start_view_min;
                const price_per_pixel = price_range / self.chart_screen_rect.height;
                const shift = dy * price_per_pixel;

                self.x_offset = self.drag_start_x_offset - dx / self.candle_slot;
                self.view_min = self.drag_start_view_min + shift;
                self.view_max = self.drag_start_view_max + shift;
            }
        }

        if (rl.isMouseButtonReleased(.left)) {
            self.drag_start_mouse = null;
        }

        if (rl.isKeyPressed(.r)) {
            const mm = calcMinMax(self.candles);
            const pad = (mm.@"1" - mm.@"0") * 0.05;
            self.view_min = mm.@"0" - pad;
            self.view_max = mm.@"1" + pad;
            self.x_offset = 0;
            self.candle_slot = CANDLE_SLOT;
            self.candle_width = CANDLE_WIDTH;
        }
    }
};

