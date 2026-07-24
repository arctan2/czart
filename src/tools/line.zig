const std = @import("std");
const rl = @import("raylib");
const CandleChart = @import("charts").CandleChart;
const Self = @This();
const Region = @import("region");
const Layout = @import("layout");

start: f32,
end: f32,
layout: *Layout,

pub fn init(_: std.mem.Allocator, _: *Layout) !*Region {
}
