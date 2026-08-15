const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const common = @import("common");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const Timeframe = common.Timeframe;
const MinMax = common.MinMax;
const DateFormatter = common.DateFormatter;
const ActiveIndicators = @import("../active_indicators.zig");
const Region = @import("region");
const defaults = @import("defaults");
const tools = @import("tools");

const Self = @This();

const INDICATOR_LABEL_GAP = 10;
const INDICATOR_LABEL_PAD = 20;

timeframe: Timeframe = .m1,
layout: *Layout,
candle_chart: *charts.CandleChart,
region: Region,
active_indicators: *ActiveIndicators,
cur_edit_idx: ?usize = null,
drag_start_view_x: MinMax = .{ .min = 0, .max = 0 },
drag_start_view_y: MinMax = .{ .min = 0, .max = 0 },

pub fn init(
    allocator: std.mem.Allocator,
    screen_rect: *const rl.Rectangle,
    candles: []charts.CandleChart.Candle,
) !*Self {
    const self = try allocator.create(Self);
    var candle_chart = try allocator.create(charts.CandleChart);
    candle_chart.* = .init(screen_rect, candles);

    self.* = .{
        .layout = &candle_chart.layout,
        .candle_chart = candle_chart,
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .getLayoutFn = getLayoutFnRegion,
            .getLayoutWithViewYFn = getLayoutWithViewYFnRegion,
            .destroyFn = deinitRegion,
        },
        .active_indicators = try .init(allocator, candle_chart)
    };

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.destroy(self.candle_chart);
    allocator.destroy(self);
}

fn drawIndicatorLabels(self: *Self, allocator: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    var row: usize = 0;
    for(self.active_indicators.list.items, 0..) |ind, idx| {
        const y = (defaults.INDICATOR_FONT_SIZE + INDICATOR_LABEL_GAP) * @as(f32, @floatFromInt(row));
        const is_drawn = try ind.drawLabel(
            allocator,
            .{
                .x = self.layout.left + INDICATOR_LABEL_PAD,
                .y = INDICATOR_LABEL_PAD + self.layout.top + y
            },
            (ctx.focused == @as(*anyopaque, @ptrCast(self))) and (idx == self.cur_edit_idx),
            resources
        );

        if(is_drawn) {
            row += 1;
        }
    }
}

fn draw(self: *Self, allocator: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    rl.drawRectangleV(
        .{ .x = self.layout.left, .y = self.layout.top },
        .{ .x = self.layout.width, .y = self.layout.height },
        Resources.CHART_BG
    );

    self.candle_chart.drawYAxis(resources);
    try self.candle_chart.drawXAxis(allocator, resources);
    self.candle_chart.drawCandles();
    if(rl.checkCollisionPointRec(rl.getMousePosition(), self.candle_chart.layout.getRect())) {
        try self.candle_chart.drawCrosshair(allocator, self.layout, &self.candle_chart.view.y, resources);
    }

    try self.drawIndicatorLabels(allocator, ctx, resources);
}

fn scroll(self: *Self, ctx: *Region.EventCtx, change_time_axis: bool) void {
    const mouse = rl.getMousePosition();

    if (change_time_axis) {
        const cursor_index = self.candle_chart.screenXToIndex(mouse.x);
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;
        const new_min = cursor_index + (self.candle_chart.view.x.min - cursor_index) * factor;
        const new_max = cursor_index + (self.candle_chart.view.x.max - cursor_index) * factor;
        const diff = new_max - new_min;

        const max_points_in_view: f32 = @floatFromInt(self.candle_chart.candles.len * 2 + 64);
        if (diff > 4 and diff < max_points_in_view) {
            self.candle_chart.view.x.min = new_min;
            self.candle_chart.view.x.max = new_max;
        }
    } else {
        const cursor_price = charts.CandleChart.screenToViewY(self.layout, &self.candle_chart.view.y, mouse.y);
        const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;

        const new_min = cursor_price + (self.candle_chart.view.y.min - cursor_price) * factor;
        const new_max = cursor_price + (self.candle_chart.view.y.max - cursor_price) * factor;
        const diff = new_max - new_min;
        if (diff > 0.001 and diff < 3_000_000_000) {
            self.candle_chart.view.y.min = new_min;
            self.candle_chart.view.y.max = new_max;
        }
    }
}

fn isExcludedIdx(self: *const Self, idx: isize) bool {
    if (idx < 0 or idx >= @as(isize, @intCast(self.active_indicators.list.items.len))) {
        return false;
    }
    return switch (self.active_indicators.list.items[@intCast(idx)].impl) {
        .macd => true,
        else => false,
    };
}

fn handleEvents(self: *Self, allocator: std.mem.Allocator, ctx: *Region.EventCtx) !void {
    if (ctx.isWheelScroll()) {
        if (ctx.isHorizontalScroll()) {
            const scroll_x_multiplier = self.candle_chart.view.x.range() / 10;
            self.candle_chart.view.x.min -= ctx.wheel_d.x * scroll_x_multiplier;
            self.candle_chart.view.x.max -= ctx.wheel_d.x * scroll_x_multiplier;
        } else {
            self.scroll(ctx, rl.isKeyDown(.left_shift) or rl.isKeyDown(.left_control));
        }
    }

    const owns_mouse_down = ctx.tryOwnMouseDown(@ptrCast(self), self.candle_chart.layout.getRect());

    const captured_by_other = ctx.captured != null and ctx.captured != @as(*anyopaque, @ptrCast(self));

    if (ctx.cur_tool_idx != null or captured_by_other) {
        self.drag_start_view_x = self.candle_chart.view.x;
        self.drag_start_view_y = self.candle_chart.view.y;
    } else if (owns_mouse_down) {
        if (ctx.mouse_d) |mouse_d| {
            const index_per_pixel = self.drag_start_view_x.range() / self.layout.width;
            self.candle_chart.view.x.min = self.drag_start_view_x.min - mouse_d.x * index_per_pixel;
            self.candle_chart.view.x.max = self.drag_start_view_x.max - mouse_d.x * index_per_pixel;

            if(ctx.state.y_pan == 0) {
                const price_per_pixel = self.drag_start_view_y.range() / self.layout.height;
                self.candle_chart.view.y.min = self.drag_start_view_y.min + mouse_d.y * price_per_pixel;
                self.candle_chart.view.y.max = self.drag_start_view_y.max + mouse_d.y * price_per_pixel;
            }
        } else if(rl.isMouseButtonDown(.left)) {
            self.drag_start_view_x = self.candle_chart.view.x;

            if(ctx.state.mouse_left_down == 0) {
                self.drag_start_view_y = self.candle_chart.view.y;
            }
        }
    }

    if(ctx.tryFocus(@ptrCast(self), self.layout.getRect())) {
        if(self.active_indicators.list.items.len == 0) {
            return;
        }

        var idx: isize = if (self.cur_edit_idx) |s| @intCast(s) else -1;
        const is_l_shift_down = rl.isKeyDown(.left_shift);
        const max_idx: isize = @intCast(self.active_indicators.list.items.len - 1);

        if(is_l_shift_down and rl.isKeyPressed(.up)) {
            idx -= 1;
            while(idx >= 0 and self.isExcludedIdx(idx)) {
                idx -= 1;
            }
        } else if(is_l_shift_down and rl.isKeyPressed(.down)) {
            idx += 1;
            while(idx <= max_idx and self.isExcludedIdx(idx)) {
                idx += 1;
            }
        }
        idx = std.math.clamp(idx, 0, max_idx);

        self.cur_edit_idx = @intCast(idx);

        if(is_l_shift_down) {
            return;
        }

        try self.active_indicators.list.items[@intCast(idx)].handleEvents(allocator);
    }
}

pub fn handleResize(self: *Self) void {
    self.layout.height = self.layout.screen_rect.height - charts.CandleChart.X_AXIS_HEIGHT;
    self.layout.width = self.layout.screen_rect.width - charts.CandleChart.Y_AXIS_WIDTH;
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *Region.EventCtx) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));

    if(self.region.sib) |sib| {
        try sib.handleEvents(allocator, ctx);
    }

    if(self.region.child) |child| {
        try child.handleEvents(allocator, ctx);
        if(ctx.state.view_y_resize == 1) {
            return;
        }
    }

    if (try tools.tryAttachTool(allocator, ctx, &self.region, self.candle_chart)) {
        return;
    }

    try self.handleEvents(allocator, ctx);

    if (rl.isKeyPressed(.r)) {
        var mm = charts.CandleChart.calcMinMax(self.candle_chart.candles);
        mm.y.pad(charts.CandleChart.CHART_PAD);
        mm.x.pad(charts.CandleChart.CHART_PAD);
        self.candle_chart.view.y = mm.y;
        self.candle_chart.view.x = mm.x;
    }
}

fn getLayoutFnRegion(ptr: *anyopaque) ?*Layout {
    const self: *Self = @alignCast(@ptrCast(ptr));
    return self.layout;
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try self.draw(allocator, ctx, resources);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.deinit(allocator);
}

fn getLayoutWithViewYFnRegion(ptr: *anyopaque) ?Layout.WithViewY {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return .{ .layout = self.layout, .view_y = &self.candle_chart.view.y };
}

