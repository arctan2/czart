const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Resources = @import("resources");

pub const Tool = struct {
    item_index: usize,
    impl: union(enum) {
        line
    },

    pub fn deinit(self: *Tool, allocator: std.mem.Allocator) void {
        switch (self.impl) {
        }
    }

    pub fn draw(self: *const Tool, chart: *const charts.CandleChart) void {
        switch (self.impl) {
        }
    }

    pub fn drawLabel(
        self: *const Tool,
        allocator: std.mem.Allocator,
        start: rl.Vector2,
        is_focused: bool,
        resources: *Resources
    ) !bool {
        return switch (self.impl) {
        };
    }

    pub fn handleEvents(self: *Tool, allocator: std.mem.Allocator) !void {
        switch (self.impl) {
        }
    }
};
