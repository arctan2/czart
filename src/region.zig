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
        view_y_resize: u1 = 0,
        y_pan: u1 = 0,
        mouse_left_down: u1 = 0,
        focus: u1 = 0,
    };

    zoom_sensitivity: f32 = 0.05,
    drag_start_mouse: ?rl.Vector2 = null,
    mouse_d: ?rl.Vector2 = null,
    wheel_d: rl.Vector2 = .{ .x = 0, .y = 0 },
    state: EventState = .{},
    captured: ?*anyopaque = null,
    focused: ?*anyopaque = null,
    cur_tool_idx: ?usize = null,

    pub fn tryOwnMouseDown(self: *EventCtx, ptr: *anyopaque, rect: rl.Rectangle) bool {
        if (self.captured) |c| return c == ptr;
        if (!rl.checkCollisionPointRec(rl.getMousePosition(), rect)) return false;
        if (rl.isMouseButtonDown(.left)) {
            self.captured = ptr;
            self.state.mouse_left_down = 1;
        }
        return true;
    }

    pub fn tryFocus(self: *EventCtx, ptr: *anyopaque, rect: rl.Rectangle) bool {
        if (self.focused) |f| return f == ptr;
        if (!rl.checkCollisionPointRec(rl.getMousePosition(), rect)) return false;
        if (rl.isMouseButtonPressed(.left)) {
            self.focused = ptr;
            self.state.focus = 1;
        }
        return true;
    }

    pub inline fn isWheelScroll(self: *const EventCtx) bool {
        return @abs(self.wheel_d.x) > deadzone or @abs(self.wheel_d.y) > deadzone;
    }

    pub inline fn isHorizontalScroll(self: *const EventCtx) bool {
        return @abs(self.wheel_d.x) > @abs(self.wheel_d.y);
    }

    pub fn isAnyKeyReleased(keys: []const rl.KeyboardKey) bool {
        for(keys) |k| {
            if(rl.isKeyReleased(k)) {
                return true;
            }
        }
        return false;
    }
};

pub fn emptyChildWillDestroyFn(_: *anyopaque, _: *Self) void {
}

pub fn emptyGetLayoutFn(_: *anyopaque) ?*Layout {
    return null;
}

pub fn emptyGetLayoutWithViewYFn(_: *anyopaque) ?Layout.WithViewY {
    return null;
}

ptr: *anyopaque,
parent: ?*Self = null,
child: ?*Self = null,
sib: ?*Self = null,

handleEventsFn: *const fn(*anyopaque, allocator: std.mem.Allocator, event_ctx: *EventCtx) error{ OutOfMemory }!void,
drawFn: *const fn(*anyopaque, allocator: std.mem.Allocator, event_ctx: *EventCtx, resources: *Resources) error{ OutOfMemory }!void,
getLayoutFn: *const fn(*anyopaque) ?*Layout = emptyGetLayoutFn,
getLayoutWithViewYFn: *const fn(*anyopaque) ?Layout.WithViewY = emptyGetLayoutWithViewYFn,
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

pub fn detachChild(self: *Self, child: *Self, child_sib: ?*Self) void {
    if (self.child == null) return;

    if (self.child.? == child) {
        self.child = child_sib;
    } else {
        var cur = self.child.?;
        while (cur.sib) |next| {
            if (next == child) {
                cur.sib = child_sib;
                break;
            }
            cur = next;
        }
    }
}

pub fn childWillDestroy(self: *Self, child: *Self) void {
    self.childWillDestroyFn(self.ptr, child);
}

pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
    while (self.child) |child| {
        self.child = child.sib;
        child.destroy(allocator);
    }

    const parent = self.parent;
    const sib = self.sib;

    if(parent) |p| p.childWillDestroy(self);
    self.destroyFn(self.ptr, allocator);
    if(parent) |p| p.detachChild(self, sib);
}

pub fn getPrevSib(self: *Self) ?*Self {
    if(self.parent) |parent| {
        if(parent.child == self) return null;

        var cur = parent.child;
        while(cur) |c| {
            if(c.sib == self) return c;
            cur = c.sib;
        }
    }
    return null;
}

pub fn appendChild(self: *Self, region: *Self) void {
    if(self.child) |child| {
        child.appendSib(region);
    } else {
        self.child = region;
        region.parent = self;
    }
}

pub fn appendSib(self: *Self, region: *Self) void {
    if(self.sib) |sib| {
        sib.appendSib(region);
    } else {
        self.sib = region;
        region.parent = self.parent;
    }
}

pub fn insertChild(self: *Self, region: *Self) void {
    if(self.child) |child| region.sib = child;
    self.child = region;
    region.parent = self;
}

pub fn insertAsPrevSib(self: *Self, region: *Self) void {
    if(self.parent == null) return;
    (if(self.getPrevSib()) |sib| sib.sib else self.parent.?.child) = region;
    region.sib = self;
    region.parent = self.parent;
}

pub fn getLayout(self: *Self) ?*Layout {
    return self.getLayoutFn(self.ptr);
}

pub fn getLayoutWithViewY(self: *Self) ?Layout.WithViewY {
    return self.getLayoutWithViewYFn(self.ptr);
}

