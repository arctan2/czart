const std = @import("std");
const rl = @import("raylib");
const Region = @import("region");
const CandleChart = @import("charts").CandleChart;
const EventCtx = Region.EventCtx;
const Layout = @import("layout");

pub const Line = @import("line.zig");

pub const ToolKind = enum(usize) {
    line_seg = 0,
    ray = 1,
    ex_line = 2,

    pub fn fromIndex(idx: usize) ?ToolKind {
        return switch (idx) {
            0 => .line_seg,
            1 => .ray,
            2 => .ex_line,
            else => null,
        };
    }
};

pub fn createRegion(
    allocator: std.mem.Allocator,
    kind: ToolKind,
    candle_chart: *CandleChart,
    layout_vy: Layout.WithViewY,
) !?*Region {
    return switch (kind) {
        .line_seg => try Line.init(allocator, .line_seg, candle_chart, layout_vy),
        .ray => try Line.init(allocator, .ray, candle_chart, layout_vy),
        .ex_line => try Line.init(allocator, .ex_line, candle_chart, layout_vy),
    };
}

pub fn tryAttachTool(
    allocator: std.mem.Allocator,
    ctx: *EventCtx,
    parent: *Region,
    candle_chart: *CandleChart,
) !bool {
    const idx = ctx.cur_tool_idx orelse return false;

    if (!rl.isMouseButtonPressed(.left)) return false;

    if(parent.getLayoutWithViewY()) |l| {
        if (!rl.checkCollisionPointRec(rl.getMousePosition(), l.layout.getRect())) {
            return false;
        }

        const kind = ToolKind.fromIndex(idx) orelse {
            ctx.cur_tool_idx = null;
            return false;
        };

        if (try createRegion(allocator, kind, candle_chart, l)) |region| {
            parent.appendChild(region);
        }

        ctx.cur_tool_idx = null;
        return true;
    }

    return false;
}
