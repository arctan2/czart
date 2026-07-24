const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const Region = @import("region");
const EventCtx = Region.EventCtx;
const defaults = @import("defaults");
const DropDown = @import("widgets").DropDown;

const Self = @This();

const SIZE = 40;
const PAD = 40;

layout: Layout,
candle_chart: *charts.CandleChart,
tools: std.ArrayList(*Region),
tools_dropdown: DropDown,
is_active: bool = false,
button_rec: rl.Rectangle,

pub var TOOLS_LIST = [_]DropDown.Item{
    .{ .name = "Line" },
    .{ .name = "Ray" },
    .{ .name = "ExLine" },
};

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle, candle_chart: *charts.CandleChart) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .candle_chart = candle_chart,
        .tools = try .initCapacity(allocator, 0),
        .layout = .empty(screen_rect),
        .tools_dropdown = undefined,
        .button_rec = .{
            .x = self.layout.left + PAD, .y = self.layout.top + PAD,
            .width = SIZE, .height = SIZE,
        }
    };

    self.layout.left = PAD + SIZE;
    self.layout.top = PAD;
    self.handleResize();

    self.tools_dropdown = .init(&TOOLS_LIST, &self.layout);

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.tools.deinit(allocator);
    allocator.destroy(self);
}

pub fn handleResize(self: *Self) void {
    self.layout.height = @min(400, self.layout.screen_rect.height * 0.5);
    self.layout.width = @min(400, self.layout.screen_rect.width * 0.5);
}

fn drawToolsPanel(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx, resources: *Resources) !void {
    rl.drawRectangleRec(self.button_rec, .{ .r = 100, .g = 100, .b = 100, .a = 255 });

    if(self.is_active) {
        rl.drawRectangleLinesEx(self.button_rec, 2, .white);
        try self.tools_dropdown.draw(allocator, ctx, resources);
    }
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx, resources: *Resources) !void {
    for(self.tools.items) |tool| {
        try tool.draw(allocator, ctx, resources);
    }
    try self.drawToolsPanel(allocator, ctx, resources);
}

pub fn handleEvents(self: *Self, _: std.mem.Allocator, ctx: *EventCtx) !bool {
    const mouse = rl.getMousePosition();

    if(self.is_active and !rl.checkCollisionPointRec(mouse, self.layout.getRect())) {
        self.is_active = false;
        self.tools_dropdown.scroll_offset = 0;
    }

    if(rl.checkCollisionPointRec(mouse, self.button_rec)) {
        self.is_active = true;
    }

    if(self.tools_dropdown.handleEvents(ctx)) |idx| {
        std.debug.print("clicked_idx = {}\n", .{idx});
        self.is_active = false;
        self.tools_dropdown.scroll_offset = 0;
    }

    return self.is_active;
}

