const std = @import("std");
const rl = @import("raylib");
const common = @import("common");
const Resources = @import("resources");

const Self = @This();
left: f32 = 0,
top: f32 = 0,
width: f32 = 0,
height: f32 = 0,
screen_rect: *const rl.Rectangle,

pub const WithViewY = struct {
    layout: *const Self,
    view_y: *const common.MinMax
};

pub fn initRect(screen_rect: *const rl.Rectangle, rect: rl.Rectangle) Self {
    return .{
        .left = rect.x,
        .top = rect.y,
        .width = rect.width,
        .height = rect.height,
        .screen_rect = screen_rect
    };
}

pub fn empty(screen_rect: *const rl.Rectangle) Self {
    return .{ .screen_rect = screen_rect };
}

pub inline fn right(self: *const Self) f32 {
    return self.left + self.width;
}

pub inline fn bottom(self: *const Self) f32 {
    return self.top + self.height;
}

pub inline fn beginScissorMode(self: *const Self) void {
    rl.beginScissorMode(
        @intFromFloat(self.left),
        @intFromFloat(self.top),
        @intFromFloat(self.width),
        @intFromFloat(self.height),
    );
}

pub fn getRect(self: *const Self) rl.Rectangle {
    return .{
        .x = self.left,
        .y = self.top,
        .height = self.height,
        .width = self.width
    };
}

pub fn drawBox(self: *const Self, color: rl.Color) void {
    rl.drawRectangleV(.{ .x = self.left, .y = self.top }, .{ .x = self.width, .y = self.height }, color);
}

pub fn drawBoxLine(self: *const Self, color: rl.Color) void {
    rl.drawRectangleLines(
        @intFromFloat(self.left),
        @intFromFloat(self.top),
        @intFromFloat(self.width),
        @intFromFloat(self.height),
        color
    );
}

