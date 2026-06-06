const rl = @import("raylib");
const std = @import("std");

pub const Candle = struct {
    const CANDLE_WIDTH: f32 = 12;
    const CANDLE_GAP: f32 = 6;

    open: f32,
    close: f32,
    low: f32,
    high: f32,
    timestamp: u64,

    fn priceToScreenY(
        price: f32,
        view_min: f32,
        view_max: f32,
        chart_top: f32,
        chart_height: f32,
    ) f32 {
        const normalized = (price - view_min) / (view_max - view_min);
        return chart_top + chart_height * (1 - normalized);
    }

    pub fn draw(
        self: *const Candle,
        chart: *const CandleChart,
        idx: usize
    ) void {
        const wax_x = chart.chart_screen_rect.x + chart.chart_screen_rect.width -
            ((CANDLE_WIDTH + CANDLE_GAP) * (@as(f32, @floatFromInt(idx)) + 1));

        const open_y = priceToScreenY(
            self.open,
            chart.view_min,
            chart.view_max,
            chart.chart_screen_rect.y,
            chart.chart_screen_rect.height,
        );

        const close_y = priceToScreenY(
            self.close,
            chart.view_min,
            chart.view_max,
            chart.chart_screen_rect.y,
            chart.chart_screen_rect.height,
        );

        const body_top = @min(open_y, close_y);
        const body_height = @abs(open_y - close_y);

        const wick_x = wax_x + CANDLE_WIDTH / 2;
        
        const high_y = priceToScreenY(
            self.high,
            chart.view_min,
            chart.view_max,
            chart.chart_screen_rect.y,
            chart.chart_screen_rect.height,
        );

        const low_y = priceToScreenY(
            self.low,
            chart.view_min,
            chart.view_max,
            chart.chart_screen_rect.y,
            chart.chart_screen_rect.height,
        );

        const color = if (self.close >= self.open) rl.Color.green else rl.Color.red;

        rl.drawLineEx(
            .{ .x = wick_x, .y = high_y },
            .{ .x = wick_x, .y = low_y },
            2, color,
        );
        rl.drawRectangleV(
            .{ .x = wax_x, .y = body_top },
            .{ .x = CANDLE_WIDTH, .y = body_height },
            color,
        );
    }
};

pub const CandleChart = struct {
    const Self = @This();
    const PRICE_FONT_SIZE = 16;

    candles: []Candle,
    chart_screen_rect: rl.Rectangle,
    chart_screen_pad: rl.Vector2,
    camera: rl.Camera2D,
    mouse_down_pos: ?rl.Vector2 = null,
    mouse_down_camera_pos: ?rl.Vector2 = null,
    price_interval: f32 = 30,
    prev_delta: f32 = -1,
    view_min: f32 = 0,
    view_max: f32 = 0,
    font: rl.Font,

    pub fn init(chart_screen_rect: rl.Rectangle, candles: []Candle, chart_screen_pad: rl.Vector2) Self {
        var r = chart_screen_rect;
        const camera = rl.Camera2D{
            .target = .{ .x = r.x, .y = r.y },
            .offset = .{.x = 0, .y = 0},
            .rotation = 0,
            .zoom = 1,
        };

        r.x = chart_screen_pad.x;
        r.y = chart_screen_pad.y;

        var min = std.math.floatMax(f32);
        var max = std.math.floatMin(f32);

        for(candles) |c| {
            min = @min(min, c.low);
            max = @max(max, c.high);
        }

        const font = rl.loadFont("/Users/prateek/Library/Fonts/HackNerdFontMono-Bold.ttf") catch @panic("unable to load the font file");

        return .{
            .chart_screen_rect = r,
            .chart_screen_pad = chart_screen_pad,
            .candles = candles,
            .camera = camera,
            .view_min = min,
            .view_max = max,
            .font = font
        };
    }

    pub inline fn right(self: *const Self) i32 {
        return @intFromFloat(self.chart_screen_rect.x + self.chart_screen_rect.width);
    }

    pub inline fn bottom(self: *const Self) i32 {
        return @intFromFloat(self.chart_screen_rect.y + self.chart_screen_rect.height);
    }

    pub fn drawPriceAxisAndLines(self: *Self) void {
        var camera = self.camera;
        camera.target.x = 0;
        camera.target.y = 0;

        rl.beginMode2D(camera);
        defer rl.endMode2D();
        rl.beginScissorMode(
            @intFromFloat(self.chart_screen_rect.x),
            @intFromFloat(self.chart_screen_rect.y),
            @intFromFloat(self.chart_screen_rect.width),
            @intFromFloat(self.chart_screen_rect.height)
        );
        defer rl.endScissorMode();

        var price: f32 = -10_000;

        const draw_till_y = self.chart_screen_rect.height - self.camera.target.y;
        
        while (price <= draw_till_y) : (price += self.price_interval) {
            const y = Candle.priceToScreenY(price, 0, draw_till_y, 0, draw_till_y);
            var buf: [12]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{price}) catch @panic("number -> str conversion failed");
            const pos: rl.Vector2 = .{
                .x = @as(f32, @floatFromInt(self.right() - @as(i32, @intCast(text.len * 6)))) -
                    self.chart_screen_pad.x - (@as(f32, @floatFromInt(text.len)) * 2.5),
                .y = y - (PRICE_FONT_SIZE / 2),
            };

            rl.drawLine(
                0,
                @intFromFloat(y),
                self.right(),
                @intFromFloat(y),
                .{.r = 50, .g = 50, .b = 50, .a = 255},
            );

            rl.drawTextEx(self.font, text, pos, PRICE_FONT_SIZE, 2, .white);
        }
    }

    fn priceToScreen(self: *Self, price: f32) f32 {
        const t = (self.view_max - price) /
            (self.view_max - self.view_min);

        return self.chart_screen_rect.y - self.camera.target.y +
            t * self.chart_screen_rect.height;
    }

    pub fn drawCandles(self: *Self) void {
        rl.beginMode2D(self.camera);
        defer rl.endMode2D();
        rl.beginScissorMode(
            @intFromFloat(self.chart_screen_rect.x),
            @intFromFloat(self.chart_screen_rect.y),
            @intFromFloat(self.chart_screen_rect.width),
            @intFromFloat(self.chart_screen_rect.height)
        );
        defer rl.endScissorMode();

        var i = @as(isize, @intCast(self.candles.len)) - 1;
        while(i >= 0) : (i -= 1) {
            self.candles[@intCast(i)].draw(self, self.candles.len - @as(usize, @intCast(i)));
        }
    }

    pub fn draw(self: *CandleChart) void {
        rl.drawRectangleRec(self.chart_screen_rect, rl.Color{ .r = 30, .g = 30, .b = 30, .a = 255 });
        self.drawPriceAxisAndLines();
        self.drawCandles();
    }

    pub fn handleEvents(self: *CandleChart, _: f32) void {
        const mouse = rl.getMousePosition();
        const wheel_move = rl.getMouseWheelMove();
        const before = rl.getScreenToWorld2D(mouse, self.camera);
        const after = rl.getScreenToWorld2D(mouse, self.camera);

        const new_view_min = self.view_min - wheel_move;
        const new_view_max = self.view_max + wheel_move;

        const d_view = new_view_max - new_view_min;

        if(d_view > 0.1) {
            self.view_min -= rl.getMouseWheelMove();
            self.view_max += rl.getMouseWheelMove();
        }

        self.camera.target.x += before.x - after.x;
        self.camera.target.y += before.y - after.y;

        if(rl.isMouseButtonDown(.left)) {
            const mouse_down_pos = rl.getMousePosition();
            if(self.mouse_down_pos == null) {
                self.mouse_down_pos = mouse_down_pos;
                self.mouse_down_camera_pos = self.camera.target;
            }
            const dx = self.mouse_down_pos.?.x - mouse_down_pos.x;
            const dy = self.mouse_down_pos.?.y - mouse_down_pos.y;
            self.camera.target.x = self.mouse_down_camera_pos.?.x + dx / self.camera.zoom;
            self.camera.target.y = self.mouse_down_camera_pos.?.y + dy / self.camera.zoom;
        } else if(rl.isMouseButtonReleased(.left)) {
            self.mouse_down_pos = null;
            self.mouse_down_camera_pos = null;
        }
    }
};
