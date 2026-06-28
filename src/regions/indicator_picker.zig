const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const indicators = @import("indicators");
const common = @import("common");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const Region = @import("region");
const rgui = @import("raygui");
const widgets = @import("widgets");

const Self = @This();

const DEFAULT_PERIOD = 20;

var ITEMS_MAP = [_]widgets.SearchSelect.Item{
    .{ .name = "SMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "Moving average convergence divergence", .is_selected = false },
};

const ActiveIndicator = struct {
    item_index: usize,
    impl: union(enum) {
        sma: indicators.SMA,
        ema: indicators.EMA,
        macd: *indicators.MACD
    },

    fn deinit(self: *ActiveIndicator, allocator: std.mem.Allocator) void {
        switch (self.impl) {
            .sma => |*s| s.deinit(allocator),
            .ema => |*e| e.deinit(allocator),
            .macd => |m| m.region.destroy(allocator),
        }
    }

    fn draw(self: *const ActiveIndicator, chart: *const charts.CandleChart) void {
        switch (self.impl) {
            .sma => |*s| s.draw(chart),
            .ema => |*e| e.draw(chart),
            .macd => {},
        }
    }
};

is_active: bool = false,
layout: Layout,
region: Region,
search_select_widget: widgets.SearchSelect,
candle_chart: *charts.CandleChart,
active: std.ArrayList(ActiveIndicator),

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle, candle_chart: *charts.CandleChart) !*Self {
    var self = try allocator.create(Self);
    self.* = .{
        .layout = .empty(screen_rect),
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .destroyFn = deinitRegion
        },
        .search_select_widget = try .init(allocator, &ITEMS_MAP, &self.layout),
        .candle_chart = candle_chart,
        .active = .empty,
    };

    self.computeLayout();

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.active.items) |*ind| {
        switch(ind.impl) {
            .macd => {},
            else => ind.deinit(allocator)
        }
    }
    self.active.deinit(allocator);
    self.search_select_widget.deinit(allocator);
    allocator.destroy(self);
}

fn draw(self: *Self, allocator: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    for (self.active.items) |*ind| {
        ind.draw(self.candle_chart);
    }

    if (self.is_active) {
        try self.search_select_widget.draw(allocator, ctx, resources);
    }
}

fn addIndicator(self: *Self, allocator: std.mem.Allocator, item_index: usize) !void {
    const candles = self.candle_chart.candles;
    const impl: @FieldType(ActiveIndicator, "impl") = switch (item_index) {
        0 => .{ .sma = try indicators.SMA.init(allocator, candles, DEFAULT_PERIOD) },
        1 => .{ .ema = try indicators.EMA.init(allocator, candles, DEFAULT_PERIOD) },
        2 => b: {
            const macd_ind = try indicators.MACD.init(allocator, self.layout.screen_rect, self.candle_chart);
            self.region.setChild(&macd_ind.region);
            break :b .{ .macd = macd_ind };
        },
        else => return,
    };
    try self.active.append(allocator, .{ .item_index = item_index, .impl = impl });
}

fn removeIndicator(self: *Self, allocator: std.mem.Allocator, item_index: usize) void {
    var i: usize = 0;
    while (i < self.active.items.len) {
        if (self.active.items[i].item_index == item_index) {
            var ind = self.active.orderedRemove(i);
            ind.deinit(allocator);
            break;
        } else {
            i += 1;
        }
    }
}

fn toggleIndicator(self: *Self, allocator: std.mem.Allocator, item_index: usize) !void {
    const item = &ITEMS_MAP[item_index];
    if (item.is_selected) {
        self.removeIndicator(allocator, item_index);
        item.is_selected = false;
    } else {
        try self.addIndicator(allocator, item_index);
        item.is_selected = true;
    }
}

fn computeLayout(self: *Self) void {
    self.layout.width = self.layout.screen_rect.width / 2;
    self.layout.height = self.layout.screen_rect.height * 0.8;

    self.layout.left = (self.layout.screen_rect.width / 2) - (self.layout.width / 2);
    self.layout.top = self.layout.screen_rect.height * 0.1;
}

pub fn setIsActive(self: *Self, v: bool) void {
    self.is_active = v;
    @memset(self.search_select_widget.buf, 0);
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *Region.EventCtx) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));

    if(rl.isWindowResized()) {
        self.computeLayout();
    }

    if(self.region.child) |child| {
        try child.handleEvents(allocator, ctx);
        if(ctx.state.y_axis_resize == 1) {
            return;
        }
    }

    if (!self.is_active) return;
    
    const mouse = rl.getMousePosition();
    const is_mouse_click = rl.isMouseButtonPressed(.left);

    if(rl.isKeyPressed(.escape) or (is_mouse_click and !rl.checkCollisionPointRec(mouse, self.layout.getRect()))) {
        self.is_active = false;
        return;
    }

    if (self.search_select_widget.handleEvents(ctx)) |item_index| {
        try self.toggleIndicator(allocator, item_index);
    }

    return;
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try self.draw(allocator, ctx, resources);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.deinit(allocator);
}
