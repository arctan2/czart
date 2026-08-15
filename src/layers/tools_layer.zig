const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const Region = @import("region");
const EventCtx = Region.EventCtx;
const defaults = @import("defaults");
const DropDown = @import("widgets").DropDown;

const Self = @This();

const SIZE = 20;
const PAD = 25;

layout: Layout,
candle_chart: *charts.CandleChart,
tools_dropdown: DropDown,
is_dropdown_active: bool = false,
button_rec: rl.Rectangle,

pub var TOOLS_LIST = [_]DropDown.Item{
    .{ .name = "Line" },
    .{ .name = "Ray" },
    .{ .name = "ExLine" },
};

pub fn init(allocator: std.mem.Allocator, screen_rect: *const rl.Rectangle, candle_chart: *charts.CandleChart) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .candle_chart = candle_chart,
        .layout = .empty(screen_rect),
        .tools_dropdown = undefined,
        .button_rec = .{
            .x = self.layout.left + PAD, .y = self.layout.top + PAD,
            .width = SIZE, .height = SIZE,
        }
    };

    self.layout.left = PAD + SIZE;
    self.layout.top = PAD;
    self.handleResize();

    self.tools_dropdown = .init(&TOOLS_LIST, &self.layout);

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

pub fn handleResize(self: *Self) void {
    self.layout.height = @min(400, self.layout.screen_rect.height * 0.5);
    self.layout.width = @min(400, self.layout.screen_rect.width * 0.5);
}

fn drawToolsPanel(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx, resources: *Resources) !void {
    rl.drawRectangleRec(self.button_rec, .{ .r = 100, .g = 100, .b = 100, .a = 255 });

    if(self.is_dropdown_active) {
        rl.drawRectangleLinesEx(self.button_rec, 2, .white);
        try self.tools_dropdown.draw(allocator, ctx, resources);
    }
}

fn drawActiveToolBadge(self: *Self, ctx: *EventCtx, resources: *Resources) void {
    const idx = ctx.cur_tool_idx orelse return;
    if (idx >= TOOLS_LIST.len) return;
    const name = TOOLS_LIST[idx].name;

    const screen = self.layout.screen_rect;
    const text_size = resources.measureText(name, defaults.BADGE_FONT_SIZE, 0);

    const rect: rl.Rectangle = .{
        .x = screen.x + (screen.width / 2) - (text_size.x / 2) - defaults.BADGE_PAD_X,
        .y = screen.y + screen.height - text_size.y - (defaults.BADGE_PAD_Y * 2) - defaults.BADGE_BOTTOM_GAP,
        .width = text_size.x + (defaults.BADGE_PAD_X * 2),
        .height = text_size.y + (defaults.BADGE_PAD_Y * 2),
    };

    rl.drawRectangleRec(rect, defaults.BADGE_BG);
    rl.drawRectangleLinesEx(rect, 1, defaults.BADGE_BORDER);
    rl.drawTextEx(resources.font, name, .{
        .x = rect.x + defaults.BADGE_PAD_X,
        .y = rect.y + defaults.BADGE_PAD_Y,
    }, defaults.BADGE_FONT_SIZE, 0, defaults.BADGE_TEXT);
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx, resources: *Resources) !void {
    try self.drawToolsPanel(allocator, ctx, resources);
    self.drawActiveToolBadge(ctx, resources);
}

pub fn handleEvents(self: *Self, _: std.mem.Allocator, ctx: *EventCtx) !bool {
    const mouse = rl.getMousePosition();

    if(ctx.cur_tool_idx != null and rl.isKeyPressed(.escape)) {
        ctx.cur_tool_idx = null;
    }

    if(self.is_dropdown_active and !rl.checkCollisionPointRec(mouse, self.layout.getRect())) {
        self.is_dropdown_active = false;
        self.tools_dropdown.scroll_offset = 0;
    }

    if(rl.checkCollisionPointRec(mouse, self.button_rec)) {
        self.is_dropdown_active = true;
    }

    if(self.is_dropdown_active) {
        if(self.tools_dropdown.handleEvents(ctx)) |idx| {
            self.is_dropdown_active = false;
            self.tools_dropdown.scroll_offset = 0;
            ctx.cur_tool_idx = idx;
            // eat this frame so the same press that picked the item isn't also
            // consumed as the tool's placement click.
            return true;
        }
    }

    return self.is_dropdown_active;
}

