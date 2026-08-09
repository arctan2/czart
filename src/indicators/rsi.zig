const std = @import("std");
const rl = @import("raylib");
const charts = @import("charts");
const Layout = @import("layout");
const Resources = @import("resources");
const Region = @import("region");
const common = @import("common");
const defaults = @import("defaults");
const EventCtx = Region.EventCtx;
const ParamEditor = @import("param_editor.zig").ParamEditor(2);
const IndicatorRegion = @import("indicator_region.zig").IndicatorRegion(Self);

const Self = @This();
const DEFAULT_PERIOD: usize = 14;
const DEFAULT_SMA_PERIOD: usize = 14;
const RSI_LINE_COLOR: rl.Color = .{ .r = 52, .g = 131, .b = 235, .a = 255 };
const SMA_LINE_COLOR: rl.Color = .{ .r = 220, .g = 120, .b = 120, .a = 255 };

points: []f32,
sma_points: []f32,
indicator_region: *IndicatorRegion,
candle_chart: *charts.CandleChart,

period: usize = DEFAULT_PERIOD,
sma_period: usize = DEFAULT_SMA_PERIOD,

editor: ParamEditor = .{},

pub fn init(
    allocator: std.mem.Allocator,
    candle_chart: *charts.CandleChart,
) !*Self {
    const self = try allocator.create(Self);
    const points_len = candle_chart.candles.len - DEFAULT_PERIOD;
    self.* = .{
        .points = try allocator.alloc(f32, points_len),
        .sma_points = try allocator.alloc(f32, points_len - DEFAULT_SMA_PERIOD + 1),
        .indicator_region = undefined,
        .candle_chart = candle_chart,
        .period = DEFAULT_PERIOD,
        .sma_period = DEFAULT_SMA_PERIOD,
    };
    self.indicator_region = try .init(allocator, candle_chart.layout.screen_rect, self);

    return self;
}

pub fn compute(self: *Self) void {
    self.indicator_region.computeLayout();
    self.computeRSI();
    self.computeSMAOfRSI();
    self.computeMinMaxY();
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.indicator_region.restoreAboveLayout();
    allocator.free(self.points);
    allocator.free(self.sma_points);
    allocator.destroy(self.indicator_region);
    allocator.destroy(self);
}

pub fn computeMinMaxY(self: *Self) void {
    var min: f32 = std.math.inf(f32);
    var max: f32 = 0;

    for(0..self.points.len) |i| {
        min = @min(min, self.points[i]);
        max = @max(max, self.points[i]);
    }

    for(0..self.sma_points.len) |i| {
        min = @min(min, self.sma_points[i]);
        max = @max(max, self.sma_points[i]);
    }

    min = @min(min, 30);
    max = @max(max, 70);

    self.indicator_region.view_y.max = max;
    self.indicator_region.view_y.min = min;
}

pub fn reallocBuffers(self: *Self, allocator: std.mem.Allocator) !void {
    const points_len = self.candle_chart.candles.len - self.period;
    self.points = try allocator.realloc(self.points, points_len);
    self.sma_points = try allocator.realloc(self.sma_points, points_len - self.sma_period + 1);
}

fn computeRSI(self: *const Self) void {
    if (self.candle_chart.candles.len < self.period + 1) return;

    const period: f32 = @floatFromInt(self.period);

    var sum_gain: f32 = 0;
    var sum_loss: f32 = 0;

    for (1..self.period + 1) |i| {
        const diff = self.candle_chart.candles[i].close - self.candle_chart.candles[i - 1].close;
        (if(diff > 0) sum_gain else sum_loss) += @abs(diff);
    }

    var avg_gain = sum_gain / period;
    var avg_loss = sum_loss / period;

    self.points[0] = 100 - (100 / (1 + (avg_gain / avg_loss)));

    for (self.period + 1..self.candle_chart.candles.len) |i| {
        const diff = self.candle_chart.candles[i].close - self.candle_chart.candles[i - 1].close;
        const t = if(diff > 0) avg_gain else avg_loss;
        (if(diff > 0) avg_gain else avg_loss) = (t * (period - 1) + @abs(diff)) / period;
        self.points[i - self.period] = 100 - (100 / (1 + (avg_gain / avg_loss)));
    }
}

fn computeSMAOfRSI(self: *const Self) void {
    if (self.points.len < self.sma_period) return;

    const sma_period_f: f32 = @floatFromInt(self.sma_period);

    var sum: f32 = 0;
    for (self.points[0..self.sma_period]) |p| sum += p;
    self.sma_points[0] = sum / sma_period_f;

    for (self.sma_period..self.points.len) |i| {
        sum += self.points[i];
        sum -= self.points[i - self.sma_period];
        self.sma_points[i - self.sma_period + 1] = sum / sma_period_f;
    }
}

fn drawReferenceLines(self: *Self) void {
    const layout = &self.indicator_region.layout;
    layout.beginScissorMode();
    defer rl.endScissorMode();

    const levels = [_]f32{ 30, 70 };
    for (levels) |level| {
        const screen_y = self.indicator_region.toScreenY(level);
        rl.drawLineDashed(
            .{ .x = layout.left, .y = screen_y },
            .{ .x = layout.right(), .y = screen_y },
            3.0, 3.0,
            .{ .r = 100, .g = 100, .b = 250, .a = 255 },
        );
    }
}

fn hoveredValues(self: *const Self) ?struct { rsi: f32, sma: ?f32 } {
    if (self.points.len == 0) return null;

    const offset = self.period;
    const idx = self.candle_chart.getClosestCandleIdx(rl.getMousePosition().x);
    if (idx < @as(f32, @floatFromInt(offset))) return null;

    const i: usize = @intFromFloat(idx - @as(f32, @floatFromInt(offset)));
    if (i >= self.points.len) return null;

    const sma_offset = self.sma_period - 1;
    const sma: ?f32 = if (i >= sma_offset and (i - sma_offset) < self.sma_points.len)
        self.sma_points[i - sma_offset]
    else
        null;

    return .{ .rsi = self.points[i], .sma = sma };
}

pub fn drawLabel(self: *Self, allocator: std.mem.Allocator, resources: *const Resources, ctx: *const EventCtx) !void {
    const pad = 10;
    const top = self.indicator_region.layout.top + pad;
    const left = self.indicator_region.layout.left + pad;
    const is_focused = ctx.focused != null and ctx.focused.? == @as(*anyopaque, @ptrCast(self));

    try self.editor.drawLabel(
        allocator, "RSI", .{ self.period, self.sma_period }, .{ .x = left, .y = top }, resources, is_focused
    );

    if (self.hoveredValues()) |v| {
        const font_size = defaults.INDICATOR_FONT_SIZE;
        const prefix_text = try std.fmt.allocPrintSentinel(
            allocator, "RSI({d}, {d})", .{ self.period, self.sma_period }, 0
        );
        defer allocator.free(prefix_text);
        var value_x = left + resources.measureText(prefix_text, font_size, 1).x + 8;

        const rsi_text = try std.fmt.allocPrintSentinel(allocator, "{d:.2}", .{v.rsi}, 0);
        defer allocator.free(rsi_text);
        rl.drawTextEx(
            resources.font, rsi_text, .{ .x = value_x, .y = top }, font_size, 1,
            RSI_LINE_COLOR,
        );
        value_x += resources.measureText(rsi_text, font_size, 1).x + 8;

        if (v.sma) |sma| {
            const sma_text = try std.fmt.allocPrintSentinel(allocator, "{d:.2}", .{sma}, 0);
            defer allocator.free(sma_text);
            rl.drawTextEx(
                resources.font, sma_text, .{ .x = value_x, .y = top }, font_size, 1,
                SMA_LINE_COLOR,
            );
        }
    }
}

pub fn draw(self: *Self, allocator: std.mem.Allocator, resources: *const Resources, ctx: *const EventCtx) !void {
    self.indicator_region.drawYAxis(resources, false);
    self.drawReferenceLines();
    self.indicator_region.drawLineChart(self.candle_chart, self.points, RSI_LINE_COLOR, self.period);
    if (self.sma_points.len > 1) {
        self.indicator_region.drawLineChart(self.candle_chart, self.sma_points, SMA_LINE_COLOR, self.period + (self.sma_period - 1));
    }
    try self.drawLabel(allocator, resources, ctx);

    try self.indicator_region.drawResizeLineHover(allocator, self.candle_chart, resources);
}

pub fn handleKeyEvents(self: *Self, allocator: std.mem.Allocator, ctx: *EventCtx) !void {
    if(ctx.focused != @as(*anyopaque, @ptrCast(self))) return;

    var params = [2]usize{ self.period, self.sma_period };
    const changed = self.editor.handleKeyEvent(
        &params,
        .{ 1, 1 },
        .{ defaults.MAX_PERIOD, defaults.MAX_PERIOD },
    );
    self.period = params[0];
    self.sma_period = params[1];

    if (changed) {
        try self.reallocBuffers(allocator);
        self.computeRSI();
        self.computeSMAOfRSI();
    }
}
