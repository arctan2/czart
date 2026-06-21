const std = @import("std");
const rl = @import("raylib");
const common = @import("common");
const MinMax = common.MinMax;
const Resources = @import("resources");

const Self = @This();
pub const PRICE_FONT_SIZE: f32 = 14;
pub const TARGET_Y_AXIS_COUNT: f32 = 10;
pub const Y_AXIS_WIDTH: f32 = 70;
pub const X_AXIS_HEIGHT: f32 = 30;
pub const CANDLE_SLOT: f32 = 20;
pub const CANDLE_WIDTH: f32 = 18;
pub const MIN_TICK_SPACING: f32 = 300.0;
pub const CHART_PAD = 0.05;

left: f32 = 0,
top: f32 = 0,
width: f32 = 0,
height: f32 = 0,
view_x: MinMax = .{},
view_y: MinMax = .{},
screen_rect: *const rl.Rectangle,

pub fn init(screen_rect: *const rl.Rectangle, min_max: common.MinMaxYX) Self {
    var r = screen_rect.*;
    r.height -= r.y * 2;
    r.width -= r.x * 2;

    r.width -= Y_AXIS_WIDTH;
    r.height -= X_AXIS_HEIGHT;

    var mm = min_max;

    mm.x.pad(CHART_PAD);
    mm.y.pad(CHART_PAD);

    return .{
        .left = r.x,
        .top = r.y,
        .width = r.width,
        .height = r.height,
        .view_x = mm.x,
        .view_y = mm.y,
        .screen_rect = screen_rect
    };
}

pub fn indexToScreenX(self: *const Self, index: f32) f32 {
    const range = self.view_x.range();
    const t = (index - self.view_x.min) / range;
    return self.left + t * self.width;
}

pub fn screenXToIndex(self: *const Self, sx: f32) f32 {
    const t = (sx - self.left) / self.width;
    return self.view_x.min + t * self.view_x.range();
}

pub fn priceToScreenY(self: *const Self, price: f32) f32 {
    const t = (price - self.view_y.min) / self.view_y.range();
    return (self.height * (1.0 - t)) + self.top;
}

pub fn screenYToPrice(self: *const Self, y: f32) f32 {
    const t = 1.0 - ((y - self.top) / self.height);
    return self.view_y.min + t * self.view_y.range();
}

pub fn tickStride(self: *const Self) f32 {
    const candles_per_pixel = self.view_x.range() / self.width;
    const min_stride = candles_per_pixel * MIN_TICK_SPACING;
    return common.niceInterval(min_stride);
}

pub inline fn right(self: *const Self) f32 {
    return self.left + self.width;
}

pub inline fn bottom(self: *const Self) f32 {
    return self.top + self.height;
}

pub fn drawYAxis(self: *Self, resources: *const Resources) void {
    const r = self.right();
    const price_range = self.view_y.range();
    const raw_interval = price_range / TARGET_Y_AXIS_COUNT;
    const interval = common.niceInterval(raw_interval);
    const first = @ceil(self.view_y.min / interval) * interval;

    rl.drawRectangle(
        @intFromFloat(r),
        @intFromFloat(self.top),
        @intFromFloat(Y_AXIS_WIDTH),
        @intFromFloat(self.height),
        Resources.AXIS_BG,
    );

    rl.drawLineEx(
        .{ .x = r, .y = self.top },
        .{ .x = r, .y = self.top + self.height },
        1.0, Resources.AXIS_BORDER_COLOR,
    );

    var price = first;
    while (price <= self.view_y.max) : (price += interval) {
        const sy = self.priceToScreenY(price);
        const screen_y = sy;

        rl.drawLineEx(
            .{ .x = self.left, .y = screen_y },
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

pub fn getRect(self: *const Self) rl.Rectangle {
    return .{
        .x = self.left,
        .y = self.top,
        .height = self.height,
        .width = self.width
    };
}

pub fn drawBox(self: *const Self, color: rl.Color) void {
    rl.drawRectangleV(.{ .x = self.left, .y = self.top }, .{ .x = self.width, .y = self.height }, color);
}

pub fn drawBoxLine(self: *const Self, color: rl.Color) void {
    rl.drawRectangleLines(
        @intFromFloat(self.left),
        @intFromFloat(self.top),
        @intFromFloat(self.width),
        @intFromFloat(self.height),
        color
    );
}
