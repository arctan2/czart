const std = @import("std");
const rl = @import("raylib");
const rgui = @import("raygui");
const Resources = @import("resources");
const Layout = @import("layout");
const Region = @import("region");

const Self = @This();

pub const Item = struct {
    is_selected: bool,
    name: [:0]const u8
};

const ITEM_HEIGHT = 38;
const ITEM_FONT_SIZE = 18;
const ITEM_SELECTED_COLOR = rl.Color{ .r = 40, .g = 200, .b = 40, .a = 255 };
const ITEM_HOVER_COLOR = rl.Color{ .r = 30, .g = 30, .b = 30, .a = 255 };
const ITEM_PAD = 10;
const SCROLL_BAR_WIDTH = 6;
const SCROLL_BAR_COLOR = rl.Color{ .r = 230, .g = 0, .b = 180, .a = 255 };
const PANEL_COLOR = rl.Color{ .r = 15, .g = 0, .b = 15, .a = 255 };

items: []Item,
filtered: []usize,
filtered_len: usize = 0,
scroll_offset: f32 = 0,
layout: *Layout,
buf: [:0]u8,

pub fn init(allocator: std.mem.Allocator, items: []Item, layout: *Layout) !Self {
    const buf = try allocator.allocSentinel(u8, 64, 0);
    @memset(buf, 0);

    const filtered = try allocator.alloc(usize, items.len);

    var self: Self = .{
        .items = items,
        .filtered = filtered,
        .layout = layout,
        .buf = buf
    };
    self.applyFilter();
    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.buf);
    allocator.free(self.filtered);
}

fn filterText(self: *const Self) []const u8 {
    return std.mem.sliceTo(self.buf, 0);
}

fn matches(name: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    var name_buf: [128]u8 = undefined;
    var needle_buf: [128]u8 = undefined;
    if (name.len > name_buf.len or needle.len > needle_buf.len) return true;

    const lname = std.ascii.lowerString(name_buf[0..name.len], name);
    const lneedle = std.ascii.lowerString(needle_buf[0..needle.len], needle);
    return std.mem.indexOf(u8, lname, lneedle) != null;
}

fn applyFilter(self: *Self) void {
    const needle = self.filterText();
    var n: usize = 0;
    for (self.items, 0..) |it, i| {
        if (matches(it.name, needle)) {
            self.filtered[n] = i;
            n += 1;
        }
    }
    self.filtered_len = n;
}

fn scrollHeight(self: *const Self) f32 {
    return (@as(f32, @floatFromInt(self.filtered_len)) + ITEM_PAD) * ITEM_HEIGHT;
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
        .x = (self.layout.left + ITEM_PAD),
        .y = list_top + ((ITEM_HEIGHT + ITEM_PAD) * i) + self.scroll_offset,
        .width = self.layout.width - (ITEM_PAD * 2),
        .height = ITEM_HEIGHT,
    };
}

fn listTop(self: *const Self) f32 {
    const input_box_height = ITEM_HEIGHT + ITEM_PAD;
    return self.layout.top + input_box_height + ITEM_PAD;
}

fn listHeight(self: *const Self) f32 {
    const input_box_height = ITEM_HEIGHT + ITEM_PAD;
    return self.layout.height - input_box_height - (ITEM_PAD * 2);
}

pub fn draw(self: *Self, _: std.mem.Allocator, ctx: *Region.EventCtx, resources: *Resources) !void {
    self.layout.drawBox(PANEL_COLOR);
    self.layout.drawBoxLine(.{ .r = 100, .g = 100, .b = 100, .a = 255 });

    rgui.setFont(resources.font);
    rgui.setStyle(.default, .{ .default = .text_size }, 20);

    rgui.setStyle(.textbox, .{ .control = .text_color_pressed }, rl.Color.white.toInt());
    rgui.setStyle(.textbox, .{ .control = .border_width }, 0);
    rgui.setStyle(.textbox, .{ .control = .base_color_pressed }, (rl.Color{ .r = 30, .g = 30, .b = 30, .a = 255 }).toInt());
    rgui.setStyle(.textbox, .{ .control = .base_color_focused }, rl.Color.green.toInt());

    _ = rgui.textBox(
        .{
            .x = self.layout.left + ITEM_PAD,
            .y = self.layout.top + ITEM_PAD,
            .width = self.layout.width - (ITEM_PAD * 2),
            .height = ITEM_HEIGHT,
        },
        self.buf,
        true,
    );

    self.applyFilter();

    const list_top = self.listTop();
    const list_height = self.listHeight();

    rl.beginScissorMode(
        @intFromFloat(self.layout.left + ITEM_PAD),
        @intFromFloat(list_top),
        @intFromFloat(self.layout.width - (ITEM_PAD * 2)),
        @intFromFloat(list_height),
    );

    for (self.filtered[0..self.filtered_len], 0..) |item_idx, row| {
        const it = self.items[item_idx];
        const rec = self.itemRect(list_top, row);

        var color: rl.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };

        if(rl.checkCollisionPointRec(rl.getMousePosition(), rec) and !ctx.isWheelScroll()) {
            color = ITEM_HOVER_COLOR;
        }

        rl.drawRectangleRec(rec, color);

        if (it.is_selected) {
            rl.drawRectangleLinesEx(rec, 1, ITEM_SELECTED_COLOR);
        }

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
        if(scroll_height > self.layout.height) {
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
        const list_top = self.listTop();
        const list_height = self.listHeight();

        const clip: rl.Rectangle = .{
            .x = self.layout.left + ITEM_PAD,
            .y = list_top,
            .width = self.layout.width - (ITEM_PAD * 2),
            .height = list_height,
        };
        if (rl.checkCollisionPointRec(mouse, clip)) {
            for (self.filtered[0..self.filtered_len], 0..) |item_idx, row| {
                const rec = self.itemRect(list_top, row);
                if (rl.checkCollisionPointRec(mouse, rec)) {
                    return item_idx;
                }
            }
        }
    }

    return null;
}
