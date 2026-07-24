const std = @import("std");
const rl = @import("raylib");
const rgui = @import("raygui");
const Resources = @import("resources");
const Layout = @import("layout");
const Region = @import("region");

const Self = @This();

pub const Item = struct {
    name: [:0]const u8
};

const ITEM_HEIGHT = 38;
const ITEM_FONT_SIZE = 18;
const ITEM_HOVER_COLOR = rl.Color{ .r = 30, .g = 30, .b = 30, .a = 255 };
const ITEM_PAD = 10;
const SCROLL_BAR_WIDTH = 6;
const SCROLL_BAR_COLOR = rl.Color{ .r = 230, .g = 0, .b = 180, .a = 255 };
const PANEL_COLOR = rl.Color{ .r = 15, .g = 0, .b = 15, .a = 255 };

items: []Item,
scroll_offset: f32 = 0,
layout: *Layout,

pub fn init(items: []Item, layout: *Layout) Self {
    return .{
        .items = items,
        .layout = layout,
    };
}

fn scrollHeight(self: *const Self) f32 {
    return (@as(f32, @floatFromInt(self.items.len)) + ITEM_PAD) * ITEM_HEIGHT;
}

fn drawScrollBar(self: *Self, top: f32, list_height: f32) void {
    const x = self.layout.right() - SCROLL_BAR_WIDTH - 1;
    const scroll_height = self.scrollHeight();
    const h = scroll_height - (self.layout.height / 2);

    if(h < list_height) {
        return;
    }

    const ratio = list_height / scroll_height;
    const thumb_height = list_height * ratio;
    const thumb_top = top + (1 - (self.scroll_offset / h * (list_height - thumb_height)));

    rl.drawRectangleV(
        .{ .x = x, .y = top },
        .{ .x = SCROLL_BAR_WIDTH, .y = list_height },
        .{ .r = 40, .g = 40, .b = 40, .a = 255 }
    );

    rl.drawRectangleV(
        .{ .x = x, .y = thumb_top },
        .{ .x = SCROLL_BAR_WIDTH, .y = thumb_height },
        SCROLL_BAR_COLOR
    );
}

fn itemRect(self: *const Self, list_top: f32, row: usize) rl.Rectangle {
    const i: f32 = @floatFromInt(row);
    return .{
        .x = self.layout.left,
        .y = list_top + ((ITEM_HEIGHT + ITEM_PAD) * i) + self.scroll_offset,
        .width = self.layout.width,
        .height = ITEM_HEIGHT,
    };
}

pub fn draw(self: *Self, _: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    self.layout.drawBox(PANEL_COLOR);
    self.layout.drawBoxLine(.{ .r = 100, .g = 100, .b = 100, .a = 255 });

    const list_top = self.layout.top;
    const list_height = self.layout.height;

    rl.beginScissorMode(
        @intFromFloat(self.layout.left),
        @intFromFloat(list_top),
        @intFromFloat(self.layout.width),
        @intFromFloat(list_height),
    );

    for (self.items, 0..) |it, row| {
        const rec = self.itemRect(list_top, row);

        var color: rl.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };

        if(rl.checkCollisionPointRec(rl.getMousePosition(), rec) and !ctx.isWheelScroll()) {
            color = ITEM_HOVER_COLOR;
        }

        rl.drawRectangleRec(rec, color);

        rl.drawTextEx(
            resources.font, it.name,
            .{
                .x = rec.x + ITEM_PAD,
                .y = rec.y + (ITEM_HEIGHT / 2) - (ITEM_FONT_SIZE / 2)
            },
            ITEM_FONT_SIZE, 1, .white
        );
    }
    rl.endScissorMode();

    self.drawScrollBar(list_top, list_height);
}

pub fn handleEvents(self: *Self, ctx: *Region.EventCtx) ?usize {
    if(ctx.wheel_d.y != 0) {
        const scroll_height = self.scrollHeight();
        const h = scroll_height - (self.layout.height / 2);

        if(h > self.layout.height and scroll_height > self.layout.height) {
            self.scroll_offset = self.scroll_offset + (ctx.wheel_d.y / ctx.zoom_sensitivity) * 3;
            if(self.scroll_offset > 0) self.scroll_offset = 0;

            const min_scroll_offset = self.layout.height - (self.layout.height / 2) - scroll_height;

            if(self.scroll_offset < min_scroll_offset) {
                self.scroll_offset = min_scroll_offset;
            }
        }
    }

    if (rl.isMouseButtonPressed(.left) and !ctx.isWheelScroll()) {
        const mouse = rl.getMousePosition();
        const list_top = self.layout.top;
        const list_height = self.layout.height;

        const clip: rl.Rectangle = .{
            .x = self.layout.left + ITEM_PAD,
            .y = list_top,
            .width = self.layout.width - (ITEM_PAD * 2),
            .height = list_height,
        };
        if (rl.checkCollisionPointRec(mouse, clip)) {
            for (0..self.items.len) |idx| {
                const rec = self.itemRect(list_top, idx);
                if (rl.checkCollisionPointRec(mouse, rec)) {
                    return idx;
                }
            }
        }
    }

    return null;
}
