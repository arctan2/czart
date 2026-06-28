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
    const EventState = packed struct {
        y_axis_resize: u1 = 0,
        x_axis_resize: u1 = 0,
        y_pan: u1 = 0,
        view_y: u1 = 0,
    };

    zoom_sensitivity: f32 = 0.05,
    drag_start_mouse: ?rl.Vector2 = null,
    drag_start_view_x: MinMax = .{ .min = 0, .max = 0 },
    drag_start_view_y: MinMax = .{ .min = 0, .max = 0 },
    mouse_d: ?rl.Vector2 = null,
    wheel_d: rl.Vector2 = .{ .x = 0, .y = 0 },
    state: EventState = .{},
    captured: ?*anyopaque = null,

    pub fn tryOwnMouseDown(self: *EventCtx, ptr: *anyopaque, rect: rl.Rectangle) bool {
        if (self.captured) |c| return c == ptr;
        if (!rl.checkCollisionPointRec(rl.getMousePosition(), rect)) return false;
        if (rl.isMouseButtonDown(.left)) self.captured = ptr;
        return true;
    }

    pub inline fn isWheelScroll(self: *const EventCtx) bool {
        return @abs(self.wheel_d.x) > deadzone or @abs(self.wheel_d.y) > deadzone;
    }

    pub inline fn isHorizontalScroll(self: *const EventCtx) bool {
        return @abs(self.wheel_d.x) > @abs(self.wheel_d.y);
    }
};

pub fn emptyChildWillDestroyFn(_: *anyopaque, _: *Self) void {
}

ptr: *anyopaque,
parent: ?*Self = null,
child: ?*Self = null,
sib: ?*Self = null,

handleEventsFn: *const fn(*anyopaque, allocator: std.mem.Allocator, event_ctx: *EventCtx) error{ OutOfMemory }!void,
drawFn: *const fn(*anyopaque, allocator: std.mem.Allocator, event_ctx: *EventCtx, resources: *Resources) error{ OutOfMemory }!void,
childWillDestroyFn: *const fn(*anyopaque, child: *Self) void = emptyChildWillDestroyFn,
destroyFn: *const fn(*anyopaque, allocator: std.mem.Allocator) void,

pub fn draw(self: *Self, allocator: std.mem.Allocator, event_ctx: *EventCtx, resources: *Resources) !void {
    try self.drawFn(self.ptr, allocator, event_ctx, resources);

    var child = self.child;

    while (child) |c| {
        try c.draw(allocator, event_ctx, resources);
        child = c.sib;
    }

    if(self.sib) |sib| {
        try sib.draw(allocator, event_ctx, resources);
    }
}

pub fn handleEvents(self: *Self, allocator: std.mem.Allocator, event_ctx: *EventCtx) !void {
    return try self.handleEventsFn(self.ptr, allocator, event_ctx);
}

pub fn detachChild(self: *Self, child: *Self) void {
    if (self.child == null) return;

    if (self.child.? == child) {
        self.child = child.sib;
    } else {
        var cur = self.child.?;
        while (cur.sib) |next| {
            if (next == child) {
                cur.sib = child.sib;
                break;
            }
            cur = next;
        }
    }

    child.parent = null;
    child.sib = null;
}

pub fn childWillDestroy(self: *Self, child: *Self) void {
    self.childWillDestroyFn(self.ptr, child);
}

pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
    if(self.parent) |p| {
        p.childWillDestroy(self);
        p.detachChild(self);
    }

    while (self.child) |child| {
        self.child = child.sib;

        child.parent = null;
        child.sib = null;

        child.destroy(allocator);
    }

    self.destroyFn(self.ptr, allocator);
}

pub fn setChild(self: *Self, region: *Self) void {
    if(self.child) |child| {
        child.setSib(region);
    } else {
        self.child = region;
        region.parent = self;
    }
}

pub fn setSib(self: *Self, region: *Self) void {
    if(self.sib) |sib| {
        sib.setSib(region);
    } else {
        self.sib = region;
    }
}

