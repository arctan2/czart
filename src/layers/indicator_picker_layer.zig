const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const indicators = @import("indicators");
const common = @import("common");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const rgui = @import("raygui");
const widgets = @import("widgets");
const Region = @import("region");
const EventCtx = Region.EventCtx;
const ActiveIndicators = @import("../active_indicators.zig");
const ActiveIndicator = ActiveIndicators.ActiveIndicator;

const Self = @This();

const DEFAULT_PERIOD = 20;

is_active: bool = false,
layout: Layout,
search_select_widget: widgets.SearchSelect,
candle_chart: *charts.CandleChart,
pane_region: *Region,
active: *ActiveIndicators,

pub fn init(
    allocator: std.mem.Allocator,
    screen_rect: *const rl.Rectangle,
    pane_region: *Region,
    candle_chart: *charts.CandleChart,
    active_indicators: *ActiveIndicators
) !*Self {
    var self = try allocator.create(Self);
    self.* = .{
        .layout = .empty(screen_rect),
        .pane_region = pane_region,
        .search_select_widget = try .init(allocator, &ActiveIndicators.ITEMS_LIST, &self.layout),
        .candle_chart = candle_chart,
        .active = active_indicators,
    };

    self.computeLayout();

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.active.deinit(allocator);
    self.search_select_widget.deinit(allocator);
    allocator.destroy(self);
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx, resources: *Resources) !void {
    try self.active.draw(allocator, ctx, resources);

    if (self.is_active) {
        try self.search_select_widget.draw(allocator, ctx, resources);
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

pub fn handleResize(self: *Self) void {
    self.computeLayout();
}

pub fn handleEvents(self: *Self, allocator: std.mem.Allocator, ctx: *Region.EventCtx) !bool {
    if(!self.is_active) {
        self.is_active = rl.isKeyPressed(.o);
        while (rl.getCharPressed() != 0) {}
        if(self.is_active) ctx.state.focus = 1;
        return self.is_active;
    }

    ctx.state.focus = 1;

    const mouse = rl.getMousePosition();
    const is_mouse_click = rl.isMouseButtonPressed(.left);

    if(rl.isKeyPressed(.escape) or (is_mouse_click and !rl.checkCollisionPointRec(mouse, self.layout.getRect()))) {
        self.is_active = false;
        return self.is_active;
    }

    if (self.search_select_widget.handleEvents(ctx)) |item_index| {
        try self.active.toggleIndicator(allocator, self.pane_region, item_index);
    }

    return self.is_active;
}

