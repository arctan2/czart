const rl = @import("raylib");
const std = @import("std");
const common = @import("common");
const Layout = @import("layout");
const Events = @import("events").Events;
const Region = @import("region");
const Resources = @import("Resources");

const Self = @This();

layout: Layout,
region: Region,
above: *Layout,
below: *Layout,

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle, above: *Layout, below: *Layout) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .layout = .empty(screen_rect),
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .destroyFn = deinitRegion,
        },
        .above = above,
        .below = below
    };

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

fn draw(self: *Self, _: std.mem.Allocator, _: *Region.EventCtx, _: *Resources) !void {
    rl.drawLineEx(
        .{ .x = self.above.left, .y = self.above.top },
        .{ .x = self.above.right(), .y = self.above.top },
        2,
        .red
    );
}

fn handleEventsRegion(ptr: *anyopaque, _: std.mem.Allocator, _: *Region.EventCtx) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    _ = self;

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
