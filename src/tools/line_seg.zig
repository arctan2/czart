const std = @import("std");
const rl = @import("raylib");
const CandleChart = @import("charts").CandleChart;
const Region = @import("region");
const Layout = @import("layout");
const Resources = @import("resources");
const EventCtx = Region.EventCtx;

const Self = @This();

const HANDLE_RADIUS = 5;
const HIT_THICKNESS = 6;
const LINE_THICKNESS = 1.5;
const LINE_COLOR = rl.Color{ .r = 50, .g = 100, .b = 250, .a = 255 };
const HANDLE_COLOR = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

const Point = struct {
    index: f32,
    price: f32,
};

const Grab = enum { none, start, end, body };

const State = enum {
    create,
    idle,
    edit,
};

start: Point,
end: Point,
candle_chart: *CandleChart,
region: Region,
state: State = .create,
awaiting_commit: bool = false,
grab: Grab = .none,
drag_anchor: Point = .{ .index = 0, .price = 0 },
drag_start: Point = .{ .index = 0, .price = 0 },
drag_end: Point = .{ .index = 0, .price = 0 },

pub fn init(allocator: std.mem.Allocator, candle_chart: *CandleChart) !*Region {
    const self = try allocator.create(Self);
    const p = mouseToData(candle_chart);
    self.* = .{
        .start = p,
        .end = p,
        .candle_chart = candle_chart,
        .region = .{
            .ptr = @ptrCast(self),
            .drawFn = drawRegion,
            .handleEventsFn = handleEventsRegion,
            .getLayoutFn = getLayoutFnRegion,
            .destroyFn = deinitRegion,
        },
    };
    return &self.region;
}

fn layout(self: *const Self) *const Layout {
    return &self.candle_chart.layout;
}

fn toScreen(self: *const Self, p: Point) rl.Vector2 {
    return .{
        .x = self.candle_chart.indexToScreenX(p.index),
        .y = self.candle_chart.viewToScreenY(p.price),
    };
}

fn dataAt(self: *const Self, screen: rl.Vector2) Point {
    return .{
        .index = self.candle_chart.screenXToIndex(screen.x),
        .price = CandleChart.screenToViewY(&self.candle_chart.layout, &self.candle_chart.view.y, screen.y),
    };
}

fn mouseToData(candle_chart: *CandleChart) Point {
    const mouse = rl.getMousePosition();
    return .{
        .index = candle_chart.screenXToIndex(mouse.x),
        .price = CandleChart.screenToViewY(&candle_chart.layout, &candle_chart.view.y, mouse.y),
    };
}

fn hitHandle(screen_pt: rl.Vector2, mouse: rl.Vector2) bool {
    return rl.checkCollisionPointCircle(mouse, screen_pt, HANDLE_RADIUS + HIT_THICKNESS);
}

fn hitBody(self: *const Self, mouse: rl.Vector2) bool {
    return rl.checkCollisionPointLine(mouse, self.toScreen(self.start), self.toScreen(self.end), HIT_THICKNESS);
}

fn handleEvents(self: *Self, ctx: *EventCtx) void {
    const mouse = rl.getMousePosition();

    switch (self.state) {
        .create => {
            ctx.captured = @ptrCast(self);

            self.end = self.dataAt(mouse);

            if (rl.isMouseButtonReleased(.left)) {
                self.awaiting_commit = true;
            }
            if (self.awaiting_commit and rl.isMouseButtonPressed(.left)) {
                ctx.captured = null;
                self.state = .idle;
            }
            return;
        },
        .idle => {
            if (rl.isMouseButtonPressed(.left) and self.hitBody(mouse)) {
                self.state = .edit;
                self.grab = .none;
            }
            return;
        },
        .edit => {
            if (rl.isMouseButtonPressed(.left)) {
                const on_start = hitHandle(self.toScreen(self.start), mouse);
                const on_end = hitHandle(self.toScreen(self.end), mouse);
                const on_body = self.hitBody(mouse);

                if (on_start) {
                    self.grab = .start;
                } else if (on_end) {
                    self.grab = .end;
                } else if (on_body) {
                    self.grab = .body;
                    self.drag_anchor = self.dataAt(mouse);
                    self.drag_start = self.start;
                    self.drag_end = self.end;
                } else {
                    self.state = .idle;
                    return;
                }
                _ = ctx.tryOwnMouseDown(@ptrCast(self), self.layout().getRect());
            }

            if (!rl.isMouseButtonDown(.left)) {
                self.grab = .none;
                return;
            }

            if (ctx.captured != @as(*anyopaque, @ptrCast(self))) return;

            const cur = self.dataAt(mouse);
            switch (self.grab) {
                .none => {},
                .start => self.start = cur,
                .end => self.end = cur,
                .body => {
                    const di = cur.index - self.drag_anchor.index;
                    const dp = cur.price - self.drag_anchor.price;
                    self.start = .{ .index = self.drag_start.index + di, .price = self.drag_start.price + dp };
                    self.end = .{ .index = self.drag_end.index + di, .price = self.drag_end.price + dp };
                },
            }
        },
    }
}

fn draw(self: *Self) void {
    self.layout().beginScissorMode();
    defer rl.endScissorMode();

    const start = self.toScreen(self.start);
    const end = self.toScreen(self.end);

    rl.drawLineEx(start, end, LINE_THICKNESS, LINE_COLOR);

    if (self.state == .edit) {
        rl.drawCircleV(start, HANDLE_RADIUS, HANDLE_COLOR);
        rl.drawCircleV(end, HANDLE_RADIUS, HANDLE_COLOR);
        rl.drawCircleLinesV(start, HANDLE_RADIUS, LINE_COLOR);
        rl.drawCircleLinesV(end, HANDLE_RADIUS, LINE_COLOR);
    }
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));

    if (self.region.sib) |s| {
        try s.handleEvents(allocator, ctx);
    }

    self.handleEvents(ctx);
}

fn getLayoutFnRegion(ptr: *anyopaque) ?*Layout {
    const self: *Self = @alignCast(@ptrCast(ptr));
    return &self.candle_chart.layout;
}

fn drawRegion(ptr: *anyopaque, _: std.mem.Allocator, _: *EventCtx, _: *Resources) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.draw();
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    allocator.destroy(self);
}
