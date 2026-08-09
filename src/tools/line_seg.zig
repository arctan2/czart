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

const BTN_SIZE = 28;
const BTN_GAP = 14;
const BTN_BG = rl.Color{ .r = 40, .g = 40, .b = 48, .a = 235 };
const BTN_BG_HOVER = rl.Color{ .r = 200, .g = 60, .b = 60, .a = 255 };
const BTN_BORDER = rl.Color{ .r = 120, .g = 120, .b = 130, .a = 255 };
const BTN_ICON = rl.Color{ .r = 235, .g = 235, .b = 235, .a = 255 };

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
layout_vy: Layout.WithViewY,
region: Region,
state: State = .create,
awaiting_commit: bool = false,
grab: Grab = .none,
drag_anchor: Point = .{ .index = 0, .price = 0 },
drag_start: Point = .{ .index = 0, .price = 0 },
drag_end: Point = .{ .index = 0, .price = 0 },

pub fn init(allocator: std.mem.Allocator, candle_chart: *CandleChart, layout_vy: Layout.WithViewY) !*Region {
    const self = try allocator.create(Self);
    const p = mouseToData(candle_chart, layout_vy);
    self.* = .{
        .start = p,
        .end = p,
        .candle_chart = candle_chart,
        .layout_vy = layout_vy,
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

fn toScreen(self: *const Self, p: Point) rl.Vector2 {
    return .{
        .x = self.candle_chart.indexToScreenX(p.index),
        .y = CandleChart.viewToScreenYIn(self.layout_vy.layout, self.layout_vy.view_y, p.price),
    };
}

fn dataAt(self: *const Self, screen: rl.Vector2) Point {
    return .{
        .index = self.candle_chart.screenXToIndex(screen.x),
        .price = CandleChart.screenToViewY(self.layout_vy.layout, self.layout_vy.view_y, screen.y),
    };
}

fn mouseToData(candle_chart: *CandleChart, layout_vy: Layout.WithViewY) Point {
    const mouse = rl.getMousePosition();
    return .{
        .index = candle_chart.screenXToIndex(mouse.x),
        .price = CandleChart.screenToViewY(layout_vy.layout, layout_vy.view_y, mouse.y),
    };
}

fn hitHandle(screen_pt: rl.Vector2, mouse: rl.Vector2) bool {
    return rl.checkCollisionPointCircle(mouse, screen_pt, HANDLE_RADIUS + HIT_THICKNESS);
}

fn hitBody(self: *const Self, mouse: rl.Vector2) bool {
    return rl.checkCollisionPointLine(mouse, self.toScreen(self.start), self.toScreen(self.end), HIT_THICKNESS);
}

fn removeBtnRect(self: *const Self) rl.Rectangle {
    const layout = self.layout_vy.layout;
    const mid_x = (self.toScreen(self.start).x + self.toScreen(self.end).x) / 2.0;
    const x = std.math.clamp(
        mid_x - BTN_SIZE / 2.0,
        layout.left,
        layout.right() - BTN_SIZE,
    );
    return .{
        .x = x,
        .y = layout.bottom() - BTN_GAP - BTN_SIZE,
        .width = BTN_SIZE,
        .height = BTN_SIZE,
    };
}

fn handleEvents(self: *Self, ctx: *EventCtx) bool {
    const mouse = rl.getMousePosition();

    if (
        (self.state == .edit and rl.isMouseButtonPressed(.left) and
        rl.checkCollisionPointRec(mouse, self.removeBtnRect())) or
        rl.isKeyPressed(.delete) or rl.isKeyPressed(.backspace)
    ) {
        if (ctx.captured == @as(*anyopaque, @ptrCast(self))) ctx.captured = null;
        if (ctx.focused == @as(*anyopaque, @ptrCast(self))) ctx.focused = null;
        return true;
    }

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
            return false;
        },
        .idle => {
            if (rl.isMouseButtonPressed(.left) and self.hitBody(mouse)) {
                self.state = .edit;
                self.grab = .none;
            }
            return false;
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
                    return false;
                }
                _ = ctx.tryOwnMouseDown(@ptrCast(self), self.layout_vy.layout.getRect());
            }

            if (!rl.isMouseButtonDown(.left)) {
                self.grab = .none;
                return false;
            }

            if (ctx.captured != @as(*anyopaque, @ptrCast(self))) return false;

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
            return false;
        },
    }
}

fn drawRemoveBtn(self: *const Self) void {
    const rect = self.removeBtnRect();
    const hovered = rl.checkCollisionPointRec(rl.getMousePosition(), rect);

    rl.drawRectangleRec(rect, if (hovered) BTN_BG_HOVER else BTN_BG);
    rl.drawRectangleLinesEx(rect, 1, BTN_BORDER);

    const pad = 5.0;
    const l = rect.x + pad;
    const r = rect.x + rect.width - pad;
    const t = rect.y + pad;
    const b = rect.y + rect.height - pad;

    rl.drawLineEx(.{ .x = l, .y = t }, .{ .x = r, .y = b }, 1.6, BTN_ICON);
    rl.drawLineEx(.{ .x = r, .y = t }, .{ .x = l, .y = b }, 1.6, BTN_ICON);
}

fn draw(self: *Self) void {
    self.layout_vy.layout.beginScissorMode(); {
        const start = self.toScreen(self.start);
        const end = self.toScreen(self.end);

        rl.drawLineEx(start, end, LINE_THICKNESS, LINE_COLOR);

        if (self.state == .edit) {
            rl.drawCircleV(start, HANDLE_RADIUS, HANDLE_COLOR);
            rl.drawCircleV(end, HANDLE_RADIUS, HANDLE_COLOR);
            rl.drawCircleLinesV(start, HANDLE_RADIUS, LINE_COLOR);
            rl.drawCircleLinesV(end, HANDLE_RADIUS, LINE_COLOR);
        }
    } rl.endScissorMode();

    if (self.state == .edit) self.drawRemoveBtn();
}

fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));

    if (self.region.sib) |s| {
        try s.handleEvents(allocator, ctx);
    }

    if (self.handleEvents(ctx)) {
        self.region.destroy(allocator);
    }
}

fn getLayoutFnRegion(ptr: *anyopaque) ?*Layout {
    const self: *Self = @alignCast(@ptrCast(ptr));
    return @constCast(self.layout_vy.layout);
}

fn drawRegion(ptr: *anyopaque, _: std.mem.Allocator, _: *EventCtx, _: *Resources) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.draw();
}

fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    allocator.destroy(self);
}
