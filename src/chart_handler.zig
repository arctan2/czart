const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const common = @import("common");
const Layout = @import("layout").Layout;
const Events = @import("events").Events;
const Timeframe = common.Timeframe;
const MinMax = common.MinMax;
const DateFormatter = common.DateFormatter;
const Candle = charts.CandleChart.Candle;

pub const ChartHandler = struct {
    const Self = @This();

    timeframe: Timeframe = .m1,
    layout: Layout,
    events: Events,
    candle_chart: charts.CandleChart,

    date_formatter: DateFormatter,

    pub fn init(allocator: std.mem.Allocator, screen_rect: rl.Rectangle, candles: []Candle) Self {
        const candle_chart: charts.CandleChart = .{ .candles = candles };
        const layout: Layout = .init(screen_rect, candle_chart.calcMinMax());

        return .{
            .layout = layout,
            .candle_chart = candle_chart,
            .events = .{},
            .date_formatter = DateFormatter{ .allocator = allocator }
        };
    }

    fn drawYAxis(self: *Self) void {
        const chart_top = self.layout.chartTop();
        const right = self.layout.chartRight();

        const price_range = self.layout.view_y.range();
        const raw_interval = price_range / Layout.TARGET_Y_AXIS_COUNT;
        const interval = common.niceInterval(raw_interval);
        const first = @ceil(self.layout.view_y.min / interval) * interval;

        var price = first;
        while (price <= self.layout.view_y.max) : (price += interval) {
            const sy = self.layout.priceToScreenY(price);
            const screen_y = chart_top + sy;

            rl.drawLineEx(
                .{ .x = self.layout.chartLeft(), .y = screen_y },
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
            const label_y = screen_y - Layout.PRICE_FONT_SIZE / 2.0;
            rl.drawTextEx(self.layout.font, text, .{ .x = label_x, .y = label_y }, Layout.PRICE_FONT_SIZE, 1, .white);
        }
    }

    fn drawXAxis(self: *Self) void {
        const axis_y = self.layout.chartBottom();
        const label_y = axis_y + 8.0;

        const stride = self.layout.tickStride();
        const first_tick = @ceil(self.layout.view_x.min / stride) * stride;
        const shows_time = self.timeframe.showsTime();

        var index: f32 = first_tick;
        while (index <= self.layout.view_x.max) : (index += stride) {
            const sx = self.layout.indexToScreenX(index);
            if (sx < self.layout.chartLeft() or sx > self.layout.chartRight()) continue;

            rl.drawLineEx(
                .{ .x = sx, .y = self.layout.chart_screen_rect.y },
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

            const ts = self.candle_chart.indexToTs(index);
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
            const text_size = rl.measureTextEx(self.layout.font, textZ, Layout.PRICE_FONT_SIZE, 1);
            const label_x = sx - text_size.x / 2.0;
            rl.drawTextEx(self.layout.font, textZ, .{ .x = label_x, .y = label_y }, Layout.PRICE_FONT_SIZE, 1, .white);
        }
    }

    fn computeSMA(self: *Self, points: []rl.Vector2, period: usize) void {
        var sum: f32 = 0;

        for (self.candles[0..period]) |candle| {
            sum += candle.close;
        }

        points[0] = .{
            .x = self.indexToScreenX(@floatFromInt(period - 1)),
            .y = self.priceToScreenY(sum / @as(f32, @floatFromInt(period))),
        };

        for (period..self.candles.len) |i| {
            sum += self.candles[i].close;
            sum -= self.candles[i - period].close;

            points[i - period + 1] = .{
                .x = self.indexToScreenX(@floatFromInt(i)),
                .y = self.priceToScreenY(sum / @as(f32, @floatFromInt(period))),
            };
        }
    }

    fn drawSMA(self: *Self) void {
        rl.beginScissorMode(
            @intFromFloat(self.layout.chartLeft()),
            @intFromFloat(self.layout.chartTop()),
            @intFromFloat(self.layout.chart_screen_rect.width),
            @intFromFloat(self.layout.chart_screen_rect.height),
        );
        defer rl.endScissorMode();

        self.computeSMA(self.sma_50_points, 50);
        rl.drawSplineCatmullRom(self.sma_50_points, 1, .blue);
    }

    pub fn draw(self: *Self, _: std.mem.Allocator) void {
        const right = self.layout.chartRight();

        rl.drawRectangleRec(self.layout.chart_screen_rect, .{ .r = 20, .g = 20, .b = 25, .a = 255 });

        const axis_bg: rl.Color = .{ .r = 30, .g = 20, .b = 30, .a = 255 };
        const axis_border_color: rl.Color = .{ .r = 160, .g = 60, .b = 160, .a = 255 };

        rl.drawRectangle(
            @intFromFloat(right),
            @intFromFloat(self.layout.screen_rect.y),
            @intFromFloat(Layout.Y_AXIS_WIDTH),
            @intFromFloat(self.layout.chart_screen_rect.height),
            axis_bg,
        );

        rl.drawRectangle(
            @intFromFloat(self.layout.chartLeft()),
            @intFromFloat(self.layout.chartBottom()),
            @intFromFloat(self.layout.chart_screen_rect.width + Layout.Y_AXIS_WIDTH),
            @intFromFloat(Layout.X_AXIS_HEIGHT),
            axis_bg,
        );

        rl.drawLineEx(
            .{ .x = right, .y = self.layout.screen_rect.y },
            .{ .x = right, .y = self.layout.screen_rect.y + self.layout.chart_screen_rect.height },
            1.0, axis_border_color,
        );

        rl.drawLineEx(
            .{ .x = self.layout.chart_screen_rect.x, .y = self.layout.chartBottom() },
            .{ .x = right, .y = self.layout.chartBottom() },
            1.0, axis_border_color,
        );

        self.drawYAxis();
        self.drawXAxis();
        self.candle_chart.drawCandles(&self.layout);
        self.candle_chart.drawCrosshair(&self.layout, &self.date_formatter);
    }


    pub fn handleEvents(self: *Self) void {
        self.events.handleEvents(&self.layout, self.candle_chart.candles.len);

        if (rl.isKeyPressed(.r)) {
            var mm = self.candle_chart.calcMinMax();
            mm.y.pad(Layout.CHART_PAD);
            mm.x.pad(Layout.CHART_PAD);
            self.layout.view_y = mm.y;
            self.layout.view_x = mm.x;
        }
    }
};
