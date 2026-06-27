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

const Self = @This();

layout: Layout,
region: Region,
buf: [:0]u8,

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
        .buf = try allocator.allocSentinel(u8, 64, 0)
    };

    for(0..self.buf.len) |i| {
        self.buf[i] = 0;
    }

    self.computeLayout();

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
    allocator.free(self.buf);
}

fn draw(self: *Self, _: std.mem.Allocator, resources: *Resources) void {
    rl.drawRectangleV(
        .{ .x = self.layout.left, .y = self.layout.top },
        .{ .x = self.layout.width, .y = self.layout.height },
        .{ .r = 0, .g = 0, .b = 0, .a = 255 }
    );

    rgui.setFont(resources.font);
    rgui.setStyle(.default, .{ .default = .text_size }, 20);

    // Background inside the textbox
    rgui.setStyle(.default, .{ .default = .background_color }, 245);

    // Text
    rgui.setStyle(.textbox, .{ .control = .text_color_pressed }, rl.Color.white.toInt());
    rgui.setStyle(.textbox, .{ .control = .border_width }, 0);
    rgui.setStyle(.textbox, .{ .control = .base_color_pressed }, (rl.Color{ .r = 30, .g = 30, .b = 30, .a = 255 }).toInt());
    rgui.setStyle(.textbox, .{ .control = .base_color_focused }, rl.Color.green.toInt());

    _ = rgui.textBox(
        .{
            .x = self.layout.left + 10,
            .y = self.layout.top + 10,
            .width = self.layout.width - 20,
            .height = 38,
        },
        self.buf,
        true,
    );
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

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, _: *Region.EventCtx) !bool {
    var self: *Self = @ptrCast(@alignCast(ptr));

    if(rl.isWindowResized()) {
        self.computeLayout();
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

