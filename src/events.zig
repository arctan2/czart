const rl = @import("raylib");
const common = @import("common");
const Layout = @import("layout");
const MinMax = common.MinMax;

pub const Events = struct {
    const Self = @This();
    zoom_sensitivity: f32 = 0.05,
    drag_start_mouse: ?rl.Vector2 = null,
    drag_start_view_x: MinMax = .{ .min = 0, .max = 0 },
    drag_start_view_y: MinMax = .{ .min = 0, .max = 0 },

    pub fn scroll(
        self: *Self,
        layout: *Layout,
        wheel: f32,
        points_count: usize,
        change_candle_slot: bool,
        change_time_axis: bool,
    ) void {
        const mid_x = layout.chartRight() / 2;
        const cursor_index = layout.screenXToIndex(mid_x);
        if (change_candle_slot or change_time_axis) {
            const factor: f32 = 1 + if (wheel > 0) -self.zoom_sensitivity else self.zoom_sensitivity;
            const new_min = cursor_index + (layout.view_x.min - cursor_index) * factor;
            const new_max = cursor_index + (layout.view_x.max - cursor_index) * factor;
            const diff = new_max - new_min;

            const max_points_in_view: f32 = @floatFromInt(points_count * 2 + 64);
            if (diff > 4 and diff < max_points_in_view) {
                layout.view_x.min = new_min;
                layout.view_x.max = new_max;
            }
        } else {
            const cursor_price = (layout.view_y.max - layout.view_y.min) / 2 + layout.view_y.min;
            const factor: f32 = 1 + if (wheel > 0) -self.zoom_sensitivity else self.zoom_sensitivity;

            const new_min = cursor_price + (layout.view_y.min - cursor_price) * factor;
            const new_max = cursor_price + (layout.view_y.max - cursor_price) * factor;
            const diff = new_max - new_min;
            if (diff > 0.001 and diff < 3_000_000_000) {
                layout.view_y.min = new_min;
                layout.view_y.max = new_max;
            }
        }
    }

    pub fn handleEvents(self: *Self, layout: *Layout, points_count: usize) void {
        if(rl.isWindowResized()) {
            layout.screen_rect.height = @as(f32, @floatFromInt(rl.getScreenHeight())) - (layout.screen_rect.y * 2);
            layout.screen_rect.width = @as(f32, @floatFromInt(rl.getScreenWidth())) - (layout.screen_rect.x * 2);

            layout.chart_screen_rect.height = layout.screen_rect.height - Layout.X_AXIS_HEIGHT;
            layout.chart_screen_rect.width = layout.screen_rect.width - Layout.Y_AXIS_WIDTH;
        }

        const mouse = rl.getMousePosition();
        const wheel = rl.getMouseWheelMoveV();

        const wdx = wheel.x * self.zoom_sensitivity;
        const wdy = wheel.y * self.zoom_sensitivity;

        const deadzone = 0.01;

        if (@abs(wdx) > deadzone or @abs(wdy) > deadzone) {
            if (@abs(wdx) > @abs(wdy)) {
                const scroll_x_multiplier = layout.view_x.range() / 10;
                layout.view_x.min -= wdx * scroll_x_multiplier;
                layout.view_x.max -= wdx * scroll_x_multiplier;
            } else {
                self.scroll(layout, wdy, points_count, rl.isKeyDown(.left_shift), rl.isKeyDown(.left_control));
            }
        }

        if (rl.isMouseButtonDown(.left)) {
            if (self.drag_start_mouse) |start| {
                const dx = mouse.x - start.x;
                const dy = mouse.y - start.y;

                const index_per_pixel = self.drag_start_view_x.range() / layout.chart_screen_rect.width;
                layout.view_x.min = self.drag_start_view_x.min - dx * index_per_pixel;
                layout.view_x.max = self.drag_start_view_x.max - dx * index_per_pixel;

                const price_per_pixel = self.drag_start_view_y.range() / layout.chart_screen_rect.height;
                layout.view_y.min = self.drag_start_view_y.min + dy * price_per_pixel;
                layout.view_y.max = self.drag_start_view_y.max + dy * price_per_pixel;
            } else {
                self.drag_start_mouse = mouse;
                self.drag_start_view_x = layout.view_x;
                self.drag_start_view_y = layout.view_y;
            }
        }

        if (rl.isMouseButtonReleased(.left)) {
            self.drag_start_mouse = null;
        }
    }
};
