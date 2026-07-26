const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");
const Resources = @import("resources");
const Region = @import("region");
const common = @import("common");
const EventCtx = Region.EventCtx;
const MinMax = common.MinMax;

pub fn IndicatorRegion(comptime Owner: type) type {
    const SPLIT_RATIO = 0.5;

    return struct {
        const Self = @This();

        layout: Layout,
        region: Region,
        view_y: MinMax = .{ .max = 2, .min = -2 },
        drag_start_view_y: MinMax = .{ .min = 0, .max = 0 },
        drag_start_view_x: MinMax = .{ .min = 0, .max = 0 },
        drag_mode: enum { none, resize, pan } = .none,
        drag_start_top: f32 = 0,
        drag_start_height: f32 = 0,
        drag_start_above_height: f32 = 0,

        pub fn init(screen_rect: *const rl.Rectangle, owner_ptr: *Owner) Self {
            return .{
                .layout = .empty(screen_rect),
                .region = .{
                    .ptr = @ptrCast(owner_ptr),
                    .drawFn = drawRegion,
                    .handleEventsFn = handleEventsRegion,
                    .getLayoutFn = getLayoutFnRegion,
                    .destroyFn = deinitRegion,
                },
            };
        }

        fn owner(self: *Self) *Owner {
            return @fieldParentPtr("indicator_region", self);
        }

        pub fn getAboveLayout(self: *Self) ?*Layout {
            return (if (self.region.getPrevSib()) |sib| sib else self.region.parent.?).getLayout();
        }

        pub fn computeLayout(self: *Self) void {
            if (self.getAboveLayout()) |above_layout| {
                const h = above_layout.height;
                above_layout.height = h * (1 - SPLIT_RATIO);
                self.layout.height = h * SPLIT_RATIO;
                self.layout.width = self.layout.screen_rect.width - charts.CandleChart.Y_AXIS_WIDTH;
                self.layout.left = above_layout.left;
                self.layout.top = above_layout.bottom();
            }
        }

        pub fn restoreAboveLayout(self: *Self) void {
            const above: *Region = if (self.region.getPrevSib()) |sib| sib else self.region.parent.?;
            if (above.getLayout()) |above_layout| {
                above_layout.height += self.layout.height;
            }
        }

        pub fn toScreenY(self: *const Self, p: f32) f32 {
            const t = (p - self.view_y.min) / self.view_y.range();
            return (self.layout.height * (1.0 - t)) + self.layout.top;
        }

        pub fn toViewY(self: *Self, y: f32) f32 {
            const t = 1.0 - ((y - self.layout.top) / self.layout.height);
            return self.view_y.min + t * self.view_y.range();
        }

        pub fn drawYAxis(self: *Self, resources: *const Resources, is_draw_lines: bool) void {
            const r = self.layout.right();
            const price_range = self.view_y.range();
            const raw_interval = price_range / 4;
            const interval = common.niceInterval(raw_interval);
            const first = @ceil(self.view_y.min / interval) * interval;

            rl.drawRectangle(
                @intFromFloat(r),
                @intFromFloat(self.layout.top),
                @intFromFloat(charts.CandleChart.Y_AXIS_WIDTH),
                @intFromFloat(self.layout.height),
                Resources.AXIS_BG,
            );

            rl.drawLineEx(
                .{ .x = r, .y = self.layout.top },
                .{ .x = r, .y = self.layout.top + self.layout.height },
                1.0, Resources.AXIS_BORDER_COLOR,
            );

            var price = first;
            while (price <= self.view_y.max) : (price += interval) {
                const screen_y = self.toScreenY(price);

                if (is_draw_lines) {
                    rl.drawLineEx(
                        .{ .x = self.layout.left, .y = screen_y },
                        .{ .x = r, .y = screen_y },
                        1.0,
                        Resources.GRID_COLOR,
                    );
                }

                var buf: [16]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{price}) catch @panic("unable to convert float -> string");

                const label_x = r + 8.0;
                const label_y = screen_y - charts.CandleChart.PRICE_FONT_SIZE / 2.0;
                rl.drawTextEx(resources.font, text, .{ .x = label_x, .y = label_y }, charts.CandleChart.PRICE_FONT_SIZE, 1, .white);
            }
        }

        pub fn drawLineChart(self: *Self, candle_chart: *const charts.CandleChart, points: []f32, color: rl.Color, start_idx: usize) void {
            std.debug.assert(points.len > 1);

            self.layout.beginScissorMode();
            defer rl.endScissorMode();

            var i, const end = candle_chart.viewXCulling(start_idx, points.len);

            while (i < end) : (i += 1) {
                const y_start = self.toScreenY(points[i]);
                const y_end = self.toScreenY(points[i + 1]);
                rl.drawLineEx(
                    .{ .x = candle_chart.indexToScreenX(@floatFromInt(i + start_idx)), .y = y_start },
                    .{ .x = candle_chart.indexToScreenX(@floatFromInt(i + 1 + start_idx)), .y = y_end },
                    1.2,
                    color,
                );
            }
        }

        pub fn drawResizeLineHover(
            self: *Self,
            allocator: std.mem.Allocator,
            candle_chart: *const charts.CandleChart,
            resources: *const Resources
        ) !void {
            const is_on_divider = rl.checkCollisionPointLine(
                rl.getMousePosition(),
                .{ .x = self.layout.left, .y = self.layout.top + 4 },
                .{ .x = self.layout.right(), .y = self.layout.top + 4 },
                8,
            );

            rl.drawLineEx(
                .{ .x = self.layout.left, .y = self.layout.top },
                .{ .x = self.layout.right(), .y = self.layout.top },
                if (is_on_divider or self.drag_mode == .resize) 4 else 1, .blue
            );

            if (rl.checkCollisionPointRec(rl.getMousePosition(), self.layout.getRect())) {
                try candle_chart.drawCrosshair(allocator, &self.layout, &self.view_y, resources);
            }
        }

        pub fn handleEvents(self: *Self, ctx: *EventCtx) void {
            if (ctx.cur_tool_idx != null) return;

            const is_mouse_left_down = rl.isMouseButtonDown(.left);
            if (!is_mouse_left_down) self.drag_mode = .none;

            if (!ctx.tryOwnMouseDown(@ptrCast(self.owner()), self.layout.getRect())) return;

            const mouse = rl.getMousePosition();

            if (self.drag_mode == .none and is_mouse_left_down) {
                const is_on_divider = rl.checkCollisionPointLine(
                    mouse,
                    .{ .x = self.layout.left, .y = self.layout.top },
                    .{ .x = self.layout.right(), .y = self.layout.top },
                    8,
                );
                self.drag_mode = if (is_on_divider) .resize else .pan;
                self.drag_start_top = self.layout.top;
                self.drag_start_height = self.layout.height;
                if (self.getAboveLayout()) |above_layout| {
                    self.drag_start_above_height = above_layout.height;
                }
            }

            if (self.drag_mode == .resize) {
                if (ctx.mouse_d) |mouse_d| {
                    self.layout.top = self.drag_start_top + mouse_d.y;
                    self.layout.height = self.drag_start_height - mouse_d.y;
                    if (self.getAboveLayout()) |above_layout| {
                        above_layout.height = self.drag_start_above_height + mouse_d.y;
                    }
                }
                return;
            }

            if (ctx.isWheelScroll() and !ctx.isHorizontalScroll() and !(rl.isKeyDown(.left_shift) or rl.isKeyDown(.left_control))) {
                const cursor_price = self.toViewY(mouse.y);
                const factor: f32 = 1 + if (ctx.wheel_d.y > 0) -ctx.zoom_sensitivity else ctx.zoom_sensitivity;

                const new_min = cursor_price + (self.view_y.min - cursor_price) * factor;
                const new_max = cursor_price + (self.view_y.max - cursor_price) * factor;
                const diff = new_max - new_min;
                if (diff > 0.001 and diff < 3_000_000_000) {
                    self.view_y.min = new_min;
                    self.view_y.max = new_max;
                }

                ctx.state.view_y_resize = 1;
                return;
            }

            if (is_mouse_left_down) {
                const candle_chart = self.owner().candle_chart;
                if (ctx.mouse_d) |mouse_d| {
                    const price_per_pixel = self.drag_start_view_y.range() / self.layout.height;
                    self.view_y.min = self.drag_start_view_y.min + mouse_d.y * price_per_pixel;
                    self.view_y.max = self.drag_start_view_y.max + mouse_d.y * price_per_pixel;
                    ctx.state.y_pan = 1;

                    const index_per_pixel = self.drag_start_view_x.range() / candle_chart.layout.width;
                    candle_chart.view.x.min = self.drag_start_view_x.min - mouse_d.x * index_per_pixel;
                    candle_chart.view.x.max = self.drag_start_view_x.max - mouse_d.x * index_per_pixel;
                } else if (rl.isMouseButtonDown(.left)) {
                    self.drag_start_view_y = self.view_y;
                    self.drag_start_view_x = candle_chart.view.x;
                }
            }
        }

        fn handleEventsRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
            const self: *Owner = @alignCast(@ptrCast(ptr));
            const region = &self.indicator_region;

            if (rl.isWindowResized()) {
                region.computeLayout();
                self.computeMinMaxY();
            }

            if (rl.isKeyPressed(.r)) {
                self.computeMinMaxY();
            }

            if (region.region.sib) |s| {
                try s.handleEvents(allocator, ctx);
            }

            if (ctx.tryFocus(ptr, region.layout.getRect())) {
                try self.handleKeyEvents(allocator, ctx);
            }

            region.handleEvents(ctx);
        }

        fn getLayoutFnRegion(ptr: *anyopaque) ?*Layout {
            const self: *Owner = @alignCast(@ptrCast(ptr));
            return &self.indicator_region.layout;
        }

        fn drawRegion(ptr: *anyopaque, allocator: std.mem.Allocator, ctx: *EventCtx, resources: *Resources) !void {
            const self: *Owner = @alignCast(@ptrCast(ptr));
            try self.draw(allocator, resources, ctx);
        }

        fn deinitRegion(ptr: *anyopaque, allocator: std.mem.Allocator) void {
            const self: *Owner = @alignCast(@ptrCast(ptr));
            self.deinit(allocator);
        }
    };
}
