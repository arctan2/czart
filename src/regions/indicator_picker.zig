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

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle) !Self {
    const self = try allocator.create(Self);
    self.* = .{
        .layout = .empty(screen_rect),
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .destroyFn = deinitRegion
        }
    };

    self.layout.x = 0;
    self.layout.y = 0;
    self.layout.width = 100;
    self.layout.height = 100;

    return self;
}

pub fn deinit(_: *Self, _: std.mem.Allocator) void {
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

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, _: *Region.EventCtx, self_region: *Region) !bool {
    var self: *Self = @ptrCast(@alignCast(ptr));

    if(rl.isWindowResized()) {
        self.layout.height = self.layout.screen_rect.height - Layout.X_AXIS_HEIGHT;
        self.layout.width = self.layout.screen_rect.width - Layout.Y_AXIS_WIDTH;
    }

    if(rl.isKeyPressed(.escape)) {
        self_region.destroy(allocator);
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

