const std = @import("std");
const rl = @import("raylib");
const Layout = @import("layout");
const EventHandler = @import("event_handler");
const common = @import("common");
const Resources = @import("resources");
const MinMax = common.MinMax;

const Self = @This();

pub const EventCtx = struct {
    const deadzone = 0.01;

    zoom_sensitivity: f32 = 0.05,
    drag_start_mouse: ?rl.Vector2 = null,
    drag_start_view_x: MinMax = .{ .min = 0, .max = 0 },
    drag_start_view_y: MinMax = .{ .min = 0, .max = 0 },
    mouse_d: ?rl.Vector2 = null,
    wheel_d: rl.Vector2 = .{ .x = 0, .y = 0 },

    pub inline fn isWheelScroll(self: *const EventCtx) bool {
        return @abs(self.wheel_d.x) > deadzone or @abs(self.wheel_d.y) > deadzone;
    }

    pub inline fn isHorizontalScroll(self: *const EventCtx) bool {
        return @abs(self.wheel_d.x) > @abs(self.wheel_d.y);
    }
};

ptr: *anyopaque,
parent: ?*Self = null,
child: ?*Self = null,
sib: ?*Self = null,
handleEventsFn: *const fn(*anyopaque, allocator: std.mem.Allocator, event_ctx: *EventCtx) error{ OutOfMemory }!void,
drawFn: *const fn(*anyopaque, allocator: std.mem.Allocator, resources: *Resources) void,
destroyFn: *const fn(*anyopaque, allocator: std.mem.Allocator) void,

pub fn draw(self: *Self, allocator: std.mem.Allocator, resources: *Resources) void {
    self.drawFn(self.ptr, allocator, resources);
}

pub fn handleEvents(self: *Self, allocator: std.mem.Allocator, event_ctx: *EventCtx) !void {
    try self.handleEventsFn(self.ptr, allocator, event_ctx);
}

pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
    self.destroyFn(self.ptr, allocator);
}

