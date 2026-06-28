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

var ITEMS_MAP = [_]widgets.SearchSelect.Item {
    .{ .name = "SMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
};

layout: Layout,
region: Region,
search_select_widget: widgets.SearchSelect,

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle) !*Self {
    var self = try allocator.create(Self);
    self.* = .{
        .layout = .empty(screen_rect),
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .destroyFn = deinitRegion
        },
        .search_select_widget = try .init(allocator, &ITEMS_MAP, &self.layout)
    };

    self.computeLayout();

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.search_select_widget.deinit(allocator);
    allocator.destroy(self);
}

fn draw(self: *Self, allocator: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    try self.search_select_widget.draw(allocator, ctx, resources);
}

fn scroll(_: *Self, _: *Region.EventCtx) void {
}

fn handleEvents(self: *Self, ctx: *Region.EventCtx) void {
    if (ctx.isWheelScroll()) {
        self.scroll(ctx);
    }
}

fn computeLayout(self: *Self) void {
    self.layout.width = self.layout.screen_rect.width / 2;
    self.layout.height = self.layout.screen_rect.height * 0.8;

    self.layout.left = (self.layout.screen_rect.width / 2) - (self.layout.width / 2);
    self.layout.top = self.layout.screen_rect.height * 0.1;
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *Region.EventCtx) !bool {
    var self: *Self = @ptrCast(@alignCast(ptr));

    if(rl.isWindowResized()) {
        self.computeLayout();
    }

    if(rl.isKeyPressed(.escape)) {
        self.region.destroy(allocator);
        return true;
    }

    self.search_select_widget.handleEvents(ctx);

    return true;
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try self.draw(allocator, ctx, resources);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.deinit(allocator);
}

