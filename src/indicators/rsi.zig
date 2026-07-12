const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");
const Resources = @import("resources");
const Region = @import("region");
const common = @import("common");
const defaults = @import("defaults");
const EventCtx = Region.EventCtx;
const MinMax = common.MinMax;
const ParamEditor = @import("param_editor.zig").ParamEditor(1);

const Self = @This();
const DEFAULT_PERIOD: usize = 14;

points: []f32,
layout: Layout,
region: Region,
candle_chart: *charts.CandleChart,
view_y: MinMax,
drag_mode: enum { none, resize, pan } = .none,
drag_start_top: f32 = 0,
drag_start_height: f32 = 0,
drag_start_above_height: f32 = 0,

period: usize = DEFAULT_PERIOD,

editor: ParamEditor = .{},

pub fn init(
    allocator: std.mem.Allocator,
    candle_chart: *charts.CandleChart,
) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .points = try allocator.alloc(f32, (candle_chart.candles.len - DEFAULT_PERIOD) + 1),
        .layout = .empty(candle_chart.layout.screen_rect),
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .getLayoutFn = getLayoutFnRegion,
            .destroyFn = deinitRegion
        },
        .candle_chart = candle_chart,
        .view_y = .{ .max = 2, .min = -2 },
        .period = DEFAULT_PERIOD,
    };

    return self;
}

fn getAboveLayout(self: *Self) ?*Layout {
    return (if(self.region.getPrevSib()) |sib| sib else self.region.parent.?).getLayout();
}

fn computeLayout(self: *Self) void {
    if(self.getAboveLayout()) |above_layout| {
        const h = above_layout.height;
        above_layout.height = h * (1 - 0.3);
        self.layout.height = h * 0.3;
        self.layout.width = self.layout.screen_rect.width - charts.CandleChart.Y_AXIS_WIDTH;
        self.layout.left = above_layout.left;
        self.layout.top = above_layout.bottom();
    }
}

pub fn compute(self: *Self) void {
    self.computeLayout();
    self.computeRSI();
    self.computeMinMaxY();
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    const above: *Region = if(self.region.getPrevSib()) |sib| sib else self.region.parent.?;

    if(above.getLayout()) |above_layout| {
        above_layout.height += self.layout.height;
    }
    allocator.free(self.points);
    allocator.destroy(self);
}

fn computeMinMaxY(self: *Self) void {
    var min: f32 = std.math.inf(f32);
    var max: f32 = 0;

    for(0..self.points.len) |i| {
        min = @min(min, self.points[i]);
        max = @max(max, self.points[i]);
    }

    self.view_y.max = max;
    self.view_y.min = min;
}

pub fn toScreenY(self: *const Self, p: f32) f32 {
    const t = (p - self.view_y.min) / self.view_y.range();
    return (self.layout.height * (1.0 - t)) + self.layout.top;
}

pub fn toViewY(self: *Self, y: f32) f32 {
    const t = 1.0 - ((y - self.layout.top) / self.layout.height);
    return self.view_y.min + t * self.view_y.range();
}

pub fn reallocBuffers(self: *Self, allocator: std.mem.Allocator) !void {
    self.points = try allocator.realloc(self.points, (self.candle_chart.candles.len - self.period) + 1);
}

fn computeRSI(self: *const Self) void {
    if (self.candle_chart.candles.len < self.period) return;

    const period: f32 = @floatFromInt(self.period);

    var sum_gain: f32 = 0;
    var sum_loss: f32 = 0;

    for (1..self.period) |i| {
        const diff = self.candle_chart.candles[i].close - self.candle_chart.candles[i - 1].close;
        (if(diff > 0) sum_gain else sum_loss) += @abs(diff);
    }

    var avg_gain = sum_gain / period;
    var avg_loss = sum_loss / period;

    self.points[0] = 100 - (100 / (1 + (avg_gain / avg_loss)));

    for (self.period..self.candle_chart.candles.len) |i| {
        const diff = self.candle_chart.candles[i].close - self.candle_chart.candles[i - 1].close;
        const t = if(diff > 0) avg_gain else avg_loss;
        (if(diff > 0) avg_gain else avg_loss) = (t * (period - 1) + @abs(diff)) / period;
        self.points[i - self.period + 1] = 100 - (100 / (1 + (avg_gain / avg_loss)));
    }
}

pub fn drawYAxis(self: *Self, resources: *const Resources) void {
    const r = self.layout.right();
    const price_range = self.view_y.range();
    const raw_interval = price_range / 4;
    const interval = common.niceInterval(raw_interval);
    const first = @ceil(self.view_y.min / interval) * interval;

    rl.drawRectangle(
        @intFromFloat(r),
        @intFromFloat(self.layout.top),
        @intFromFloat(charts.CandleChart.Y_AXIS_WIDTH),
        @intFromFloat(self.layout.height),
        Resources.AXIS_BG,
    );

    rl.drawLineEx(
        .{ .x = r, .y = self.layout.top },
        .{ .x = r, .y = self.layout.top + self.layout.height },
        1.0, Resources.AXIS_BORDER_COLOR,
    );

    var price = first;
    while (price <= self.view_y.max) : (price += interval) {
        const sy = self.toScreenY(price);
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
        const label_y = screen_y - charts.CandleChart.PRICE_FONT_SIZE / 2.0;
        rl.drawTextEx(resources.font, text, .{ .x = label_x, .y = label_y }, charts.CandleChart.PRICE_FONT_SIZE, 1, .white);
    }
}

fn drawLineChart(self: *Self, points: []f32, color: rl.Color, start_idx: usize) void {
    std.debug.assert(points.len > 1);

    rl.beginScissorMode(
        @intFromFloat(self.layout.left),
        @intFromFloat(self.layout.top),
        @intFromFloat(self.layout.width),
        @intFromFloat(self.layout.height),
    );
    defer rl.endScissorMode();

    var i, const end = self.candle_chart.viewXCulling(start_idx, points.len);

    while(i < end) : (i += 1) {
        const y_start = self.toScreenY(points[i]);
        const y_end = self.toScreenY(points[i + 1]);
        rl.drawLineEx(
            .{ .x = self.candle_chart.indexToScreenX(@floatFromInt(i + start_idx)), .y = y_start },
            .{ .x = self.candle_chart.indexToScreenX(@floatFromInt(i + 1 + start_idx)), .y = y_end },
            1.2,
            color
        );
    }
}

fn hoveredValue(self: *const Self) ?f32 {
    if (self.points.len == 0) return null;

    const offset = self.period;
    const idx = self.candle_chart.getClosestCandleIdx(rl.getMousePosition().x);
    if (idx < @as(f32, @floatFromInt(offset))) return null;

    const i: usize = @intFromFloat(idx - @as(f32, @floatFromInt(offset)));
    if (i >= self.points.len) return null;

    return self.points[i];
}

pub fn drawLabel(self: *Self, allocator: std.mem.Allocator, resources: *const Resources, ctx: *const EventCtx) !void {
    const pad = 10;
    const top = self.layout.top + pad;
    const left = self.layout.left + pad;
    const is_focused = ctx.focused != null and ctx.focused.? == @as(*anyopaque, @ptrCast(self));

    try self.editor.drawLabel(allocator, "RSI", .{ self.period }, .{ .x = left, .y = top }, resources, is_focused);

    if (self.hoveredValue()) |value| {
        const font_size = defaults.INDICATOR_FONT_SIZE;
        const prefix_text = try std.fmt.allocPrintSentinel(allocator, "RSI({d})", .{self.period}, 0);
        defer allocator.free(prefix_text);
        const prefix_w = resources.measureText(prefix_text, font_size, 1).x;
        const text = try std.fmt.allocPrintSentinel(allocator, "{d:.2}", .{value}, 0);
        defer allocator.free(text);
        rl.drawTextEx(
            resources.font,
            text,
            .{ .x = left + prefix_w + 8, .y = top },
            font_size, 1,
            .{ .r = 0, .g = 150, .b = 255, .a = 255 },
        );
    }
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, resources: *const Resources, ctx: *const EventCtx) !void {
    self.drawLineChart(self.points, .{ .r = 255, .g = 0, .b = 255, .a = 255 }, self.period);
    self.drawYAxis(resources);
    try self.drawLabel(allocator, resources, ctx);

    const is_on_divider = rl.checkCollisionPointLine(
        rl.getMousePosition(),
        .{ .x = self.layout.left, .y = self.layout.top + 4 },
        .{ .x = self.layout.right(), .y = self.layout.top + 4 },
        8
    );

    rl.drawLineEx(
        .{ .x = self.layout.left, .y = self.layout.top },
        .{ .x = self.layout.right(), .y = self.layout.top },
        if(is_on_divider or self.drag_mode == .resize) 4 else 1, .blue
    );

    if(rl.checkCollisionPointRec(rl.getMousePosition(), self.layout.getRect())) {
        try self.candle_chart.drawCrosshair(allocator, &self.layout, &self.view_y, resources);
    }
}

fn handleEvents(self: *Self, ctx: *EventCtx) void {
    const is_mouse_left_down = rl.isMouseButtonDown(.left);
    if (!is_mouse_left_down) self.drag_mode = .none;

    if(!ctx.tryOwnMouseDown(@ptrCast(self), self.layout.getRect())) return;

    const mouse = rl.getMousePosition();

    if (self.drag_mode == .none and is_mouse_left_down) {
        const is_on_divider = rl.checkCollisionPointLine(
            mouse,
            .{ .x = self.layout.left, .y = self.layout.top },
            .{ .x = self.layout.right(), .y = self.layout.top },
            8
        );
        self.drag_mode = if (is_on_divider) .resize else .pan;
        self.drag_start_top = self.layout.top;
        self.drag_start_height = self.layout.height;
        if(self.getAboveLayout()) |above_layout| {
            self.drag_start_above_height = above_layout.height;
        }
    }

    if (self.drag_mode == .resize) {
        if(ctx.mouse_d) |mouse_d| {
            self.layout.top = self.drag_start_top + mouse_d.y;
            self.layout.height = self.drag_start_height - mouse_d.y;
            if(self.getAboveLayout()) |above_layout| {
                above_layout.height = self.drag_start_above_height + mouse_d.y;
            }
        }
        return;
    }

    if (ctx.isWheelScroll() and !ctx.isHorizontalScroll() and !(rl.isKeyDown(.left_shift) or rl.isKeyDown(.left_control))) {
        const cursor_price = self.toViewY(mouse.y);
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;

        const new_min = cursor_price + (self.view_y.min - cursor_price) * factor;
        const new_max = cursor_price + (self.view_y.max - cursor_price) * factor;
        const diff = new_max - new_min;
        if (diff > 0.001 and diff < 3_000_000_000) {
            self.view_y.min = new_min;
            self.view_y.max = new_max;
        }

        ctx.state.view_y_resize = 1;
        return;
    }

    if(is_mouse_left_down) {
        if (ctx.mouse_d) |mouse_d| {
            const price_per_pixel = ctx.drag_start_view_y.range() / self.layout.height;
            self.view_y.min = ctx.drag_start_view_y.min + mouse_d.y * price_per_pixel;
            self.view_y.max = ctx.drag_start_view_y.max + mouse_d.y * price_per_pixel;
            ctx.state.y_pan = 1;
        } else if(rl.isMouseButtonDown(.left)) {
            ctx.drag_start_view_y = self.view_y;
        }
    }
}

fn handleKeyEvents(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    if(ctx.focused != @as(*anyopaque, @ptrCast(self))) return;

    var params = [1]usize{ self.period };
    const changed = self.editor.handleKeyEvent(
        &params,
        .{ 1 },
        .{ defaults.MAX_PERIOD },
    );
    self.period = params[0];

    if (changed) {
        try self.reallocBuffers(allocator);
        self.computeRSI();
    }
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    const self: *Self = @alignCast(@ptrCast(ptr));

    if(rl.isWindowResized()) {
        self.computeLayout();
        self.computeMinMaxY();
    }

    if(rl.isKeyPressed(.r)) {
        self.computeMinMaxY();
    }

    if(self.region.sib) |s| {
        try s.handleEvents(allocator, ctx);
    }

    if(ctx.tryFocus(ptr, self.layout.getRect())) {
        try self.handleKeyEvents(allocator, ctx);
    }

    self.handleEvents(ctx);
}

fn getLayoutFnRegion(ptr: *anyopaque) ?*Layout {
    const self: *Self = @alignCast(@ptrCast(ptr));
    return &self.layout;
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx, resources: *Resources) !void {
    const self: *Self = @alignCast(@ptrCast(ptr));
    try self.draw(allocator, resources, ctx);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *Self = @alignCast(@ptrCast(ptr));
    self.deinit(allocator);
}

