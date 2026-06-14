const rl = @import("raylib");
const common = @import("common");
const MinMax = common.MinMax;

pub const Layout = struct {
    const Self = @This();
    pub const PRICE_FONT_SIZE: f32 = 14;
    pub const TARGET_Y_AXIS_COUNT: f32 = 10;
    pub const Y_AXIS_WIDTH: f32 = 70;
    pub const X_AXIS_HEIGHT: f32 = 30;
    pub const CANDLE_SLOT: f32 = 20;
    pub const CANDLE_WIDTH: f32 = 18;
    pub const MIN_TICK_SPACING: f32 = 300.0;
    pub const CHART_PAD = 0.05;

    screen_rect: rl.Rectangle,
    chart_screen_rect: rl.Rectangle,
    view_x: MinMax,
    view_y: MinMax,
    font: rl.Font,

    pub fn init(screen_rect: rl.Rectangle, min_max: common.MinMaxYX) Self {
        const font = rl.loadFont("/Users/prateek/Library/Fonts/HackNerdFontMono-Bold.ttf") catch @panic("unable to load font");
        var sr = screen_rect;
        sr.height -= sr.y * 2;
        sr.width -= sr.x * 2;

        var chart_rect = sr;
        chart_rect.width -= Y_AXIS_WIDTH;
        chart_rect.height -= X_AXIS_HEIGHT;

        var mm = min_max;

        mm.x.pad(CHART_PAD);
        mm.y.pad(CHART_PAD);

        return .{
            .screen_rect = screen_rect,
            .chart_screen_rect = chart_rect,
            .view_x = mm.x,
            .view_y = mm.y,
            .font = font
        };
    }

    pub fn indexToScreenX(self: *const Self, index: f32) f32 {
        const range = self.view_x.range();
        const t = (index - self.view_x.min) / range;
        return self.chart_screen_rect.x + t * self.chart_screen_rect.width;
    }

    pub fn screenXToIndex(self: *const Self, sx: f32) f32 {
        const t = (sx - self.chart_screen_rect.x) / self.chart_screen_rect.width;
        return self.view_x.min + t * self.view_x.range();
    }

    pub fn priceToScreenY(self: *const Self, price: f32) f32 {
        const t = (price - self.view_y.min) / self.view_y.range();
        return self.chart_screen_rect.height * (1.0 - t);
    }

    pub fn screenYToPrice(self: *const Self, y: f32) f32 {
        const t = 1.0 - ((y - self.chart_screen_rect.y) / self.chart_screen_rect.height);
        return self.view_y.min + t * self.view_y.range();
    }

    pub fn tickStride(self: *const Self) f32 {
        const candles_per_pixel = self.view_x.range() / self.chart_screen_rect.width;
        const min_stride = candles_per_pixel * MIN_TICK_SPACING;
        return common.niceInterval(min_stride);
    }

    pub inline fn chartLeft(self: *const Self) f32 {
        return self.chart_screen_rect.x;
    }

    pub inline fn chartRight(self: *const Self) f32 {
        return self.chart_screen_rect.x + self.chart_screen_rect.width;
    }

    pub inline fn chartTop(self: *const Self) f32 {
        return self.chart_screen_rect.y;
    }

    pub inline fn chartBottom(self: *const Self) f32 {
        return self.chart_screen_rect.y + self.chart_screen_rect.height;
    }
};
