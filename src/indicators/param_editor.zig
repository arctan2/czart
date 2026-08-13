const std = @import("std");
const rl = @import("raylib");
const Resources = @import("resources");
const EventCtx = @import("region").EventCtx;
const defaults = @import("defaults");


pub fn ParamEditor(comptime count: usize) type {
    return struct {
        const Self = @This();
        pub const COUNT = count;

        cur_edit_idx: usize = 0,
        last_key_down_time: f32 = 0,
        key_sensitivity: f32 = defaults.DEFAULT_KEY_SENSITIVITY,

        pub fn handleKeyEvent(self: *Self, params: *[count]usize, min: [count]usize, max: [count]usize) bool {
            var changed = false;

            if (rl.isKeyPressed(.left)) {
                if (self.last_key_down_time == 0) {
                    self.cur_edit_idx = if (self.cur_edit_idx == 0) count - 1 else self.cur_edit_idx - 1;
                }
                self.last_key_down_time += self.key_sensitivity;
            }

            if (rl.isKeyPressed(.right)) {
                if (self.last_key_down_time == 0) {
                    self.cur_edit_idx = if (self.cur_edit_idx == count - 1) 0 else self.cur_edit_idx + 1;
                }
                self.last_key_down_time += self.key_sensitivity;
            }

            if (rl.isKeyDown(.up)) {
                if (self.last_key_down_time == 0) {
                    const i = self.cur_edit_idx;
                    params[i] = std.math.clamp(params[i] +| 1, min[i], max[i]);
                    changed = true;
                }
                self.last_key_down_time += self.key_sensitivity;
            }

            if (rl.isKeyDown(.down)) {
                if (self.last_key_down_time == 0) {
                    const i = self.cur_edit_idx;
                    params[i] = std.math.clamp(params[i] -| 1, min[i], max[i]);
                    changed = true;
                }
                self.last_key_down_time += self.key_sensitivity;
            }

            if (EventCtx.isAnyKeyReleased(&.{ .up, .down, .left, .right })) {
                self.last_key_down_time = 0;
                self.key_sensitivity = defaults.DEFAULT_KEY_SENSITIVITY;
            } else if (self.last_key_down_time > 1) {
                self.last_key_down_time = 0;
                self.key_sensitivity += 0.2;
            }

            return changed;
        }

        pub fn drawLabel(
            self: *const Self,
            allocator: std.mem.Allocator,
            prefix: []const u8,
            params: [count]usize,
            start: rl.Vector2,
            resources: *const Resources,
            is_focused: bool,
        ) !void {
            const font_size: f32 = defaults.INDICATOR_FONT_SIZE;

            var text_buf = std.ArrayList(u8).empty;
            defer text_buf.deinit(allocator);
            try text_buf.appendSlice(allocator, prefix);
            try text_buf.append(allocator, '(');
            inline for (0..count) |i| {
                if (i != 0) try text_buf.appendSlice(allocator, ", ");
                try text_buf.print(allocator, "{d}", .{params[i]});
            }
            try text_buf.append(allocator, ')');
            try text_buf.append(allocator, 0);

            const text: [:0]const u8 = text_buf.items[0 .. text_buf.items.len - 1 :0];
            rl.drawTextEx(resources.font, text, start, font_size, 1, .white);

            if (!is_focused) return;

            const prefix_z = try std.fmt.allocPrintSentinel(allocator, "{s}(", .{prefix}, 0);
            defer allocator.free(prefix_z);
            const param_start = resources.measureText(prefix_z, font_size, 1);

            var x: f32 = 0;
            var w: f32 = 0;
            inline for (0..count) |i| {
                const seg = if (i != count - 1)
                    try std.fmt.allocPrintSentinel(allocator, "{d}, ", .{params[i]}, 0)
                else
                    try std.fmt.allocPrintSentinel(allocator, "{d}", .{params[i]}, 0);
                defer allocator.free(seg);

                const seg_w = resources.measureText(seg, font_size, 1).x;
                if (i == self.cur_edit_idx) w = seg_w;
                if (i < self.cur_edit_idx) x += seg_w;
            }

            rl.drawRectangleV(
                .{ .x = start.x + param_start.x + x, .y = start.y },
                .{ .x = w, .y = param_start.y },
                .{ .r = 185, .g = 185, .b = 185, .a = 100 },
            );
        }
    };
}
