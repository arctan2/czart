const std = @import("std");
const rl = @import("raylib");
const Region = @import("region");
const CandleChart = @import("charts").CandleChart;
const EventCtx = Region.EventCtx;

pub const LineSeg = @import("line_seg.zig");

pub const ToolKind = enum(usize) {
    line_seg = 0,
    ray = 1,
    ex_line = 2,

    pub fn fromIndex(idx: usize) ?ToolKind {
        return switch (idx) {
            0 => .line_seg,
            else => null,
        };
    }
};

pub fn createRegion(allocator: std.mem.Allocator, kind: ToolKind, candle_chart: *CandleChart) !?*Region {
    return switch (kind) {
        .line_seg => try LineSeg.init(allocator, candle_chart),
        else => null,
    };
}

/// Attach a pending tool to `parent` when the candle pane rect is clicked.
pub fn tryAttachTool(
    allocator: std.mem.Allocator,
    ctx: *EventCtx,
    parent: *Region,
    candle_chart: *CandleChart,
) !bool {
    const idx = ctx.cur_tool_idx orelse return false;
    if (!rl.isMouseButtonPressed(.left)) return false;
    if (!rl.checkCollisionPointRec(rl.getMousePosition(), candle_chart.layout.getRect())) return false;

    const kind = ToolKind.fromIndex(idx) orelse {
        ctx.cur_tool_idx = null;
        return false;
    };

    if (try createRegion(allocator, kind, candle_chart)) |region| {
        parent.appendChild(region);
    }
    ctx.cur_tool_idx = null;
    return true;
}
