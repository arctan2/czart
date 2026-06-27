const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const indicators = @import("indicators");
const common = @import("common");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const Region = @import("region");

const Self = @This();

layout: Layout,
region: Region,

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle) !*Self {
    var self = try allocator.create(Self);
    self.* = .{
        .layout = .empty(screen_rect),
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .destroyFn = deinitRegion
        }
    };

    self.layout.left = 0;
    self.layout.top = 0;
    self.layout.width = 100;
    self.layout.height = 100;

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

fn draw(self: *Self, _: std.mem.Allocator, _: *Resources) void {
    rl.drawRectangleV(
        .{ .x = self.layout.left, .y = self.layout.top },
        .{ .x = self.layout.width, .y = self.layout.height },
        .red
    );
}

fn scroll(_: *Self, _: *Region.EventCtx) void {
}

fn handleEvents(self: *Self, ctx: *Region.EventCtx) void {
    if (ctx.isWheelScroll()) {
        self.scroll(ctx);
    }
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, _: *Region.EventCtx) !bool {
    var self: *Self = @ptrCast(@alignCast(ptr));

    if(rl.isWindowResized()) {
        self.layout.height = self.layout.screen_rect.height;
        self.layout.width = self.layout.screen_rect.width;
    }

    if(rl.isKeyPressed(.escape)) {
        self.region.destroy(allocator);
    }

    return true;
}

fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, resources: *Resources) void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.draw(allocator, resources);
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.deinit(allocator);
}

