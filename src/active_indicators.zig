const rl = @import("raylib");
const std = @import("std");
const charts = @import("charts");
const indicators = @import("indicators");
const common = @import("common");
const Layout = @import("layout");
const Events = @import("events").Events;
const Resources = @import("resources");
const rgui = @import("raygui");
const widgets = @import("widgets");
const Region = @import("region");
const EventCtx = Region.EventCtx;

const Self = @This();

const DEFAULT_PERIOD = 20;
pub var ITEMS_MAP = [_]widgets.SearchSelect.Item{
    .{ .name = "SMA", .is_selected = false },
    .{ .name = "EMA", .is_selected = false },
    .{ .name = "Bollinger Bands", .is_selected = false },
    .{ .name = "Moving average convergence divergence", .is_selected = false },
    .{ .name = "Relative Strength Index", .is_selected = false },
};

pub const ActiveIndicator = struct {
    item_index: usize,
    impl: union(enum) {
        sma: indicators.SMA,
        ema: indicators.EMA,
        bollinger_bands: indicators.BollingerBands,
        macd: *indicators.MACD,
        rsi: *indicators.RSI,
    },

    pub fn deinit(self: *ActiveIndicator, allocator: std.mem.Allocator) void {
        switch (self.impl) {
            .sma => |*s| s.deinit(allocator),
            .ema => |*e| e.deinit(allocator),
            .bollinger_bands => |*b| b.deinit(allocator),
            .macd => |m| m.indicator_region.region.destroy(allocator),
            .rsi => |r| r.indicator_region.region.destroy(allocator),
        }
    }

    pub fn draw(self: *const ActiveIndicator, chart: *const charts.CandleChart) void {
        switch (self.impl) {
            .sma => |*s| s.draw(chart),
            .ema => |*e| e.draw(chart),
            .bollinger_bands => |*b| b.draw(),
            .macd => {},
            .rsi => {},
        }
    }

    pub fn drawLabel(
        self: *const ActiveIndicator,
        allocator: std.mem.Allocator,
        start: rl.Vector2,
        is_focused: bool,
        resources: *Resources
    ) !bool {
        return switch (self.impl) {
            .sma => |*s| try s.drawLabel(allocator, start, is_focused, resources),
            .ema => |*e| try e.drawLabel(allocator, start, is_focused, resources),
            .bollinger_bands => |*b| try b.drawLabel(allocator, start, is_focused, resources),
            .macd, .rsi => false,
        };
    }

    pub fn handleEvents(self: *ActiveIndicator, allocator: std.mem.Allocator) !void {
        switch (self.impl) {
            .sma => |*s| try s.handleEvents(allocator),
            .ema => |*e| try e.handleEvents(allocator),
            .bollinger_bands => |*b| try b.handleEvents(allocator),
            .macd, .rsi => {},
        }
    }
};

list: std.ArrayList(ActiveIndicator),
candle_chart: *charts.CandleChart,

pub fn init(allocator: std.mem.Allocator, candle_chart: *charts.CandleChart) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .list = try .initCapacity(allocator, 0),
        .candle_chart = candle_chart
    };

    return self;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.list.items) |*ind| {
        switch(ind.impl) {
            .macd => {},
            else => ind.deinit(allocator)
        }
    }
    self.list.deinit(allocator);
    allocator.destroy(self);
}

pub fn draw(self: *Self, _: std.mem.Allocator, _: *EventCtx, _: *Resources) !void {
    for (self.list.items) |*ind| {
        ind.draw(self.candle_chart);
    }
}

fn addIndicator(self: *Self, allocator: std.mem.Allocator, pane_region: *Region, item_index: usize) !void {
    const impl: @FieldType(ActiveIndicator, "impl") = switch (item_index) {
        0 => .{ .sma = try indicators.SMA.init(allocator, self.candle_chart, DEFAULT_PERIOD) },
        1 => .{ .ema = try indicators.EMA.init(allocator, self.candle_chart, DEFAULT_PERIOD) },
        2 => .{ .bollinger_bands = try indicators.BollingerBands.init(allocator, self.candle_chart) },
        3 => b: {
            const macd_ind = try indicators.MACD.init(allocator, self.candle_chart);
            pane_region.appendChild(&macd_ind.indicator_region.region);
            macd_ind.compute();
            break :b .{ .macd = macd_ind };
        },
        4 => b: {
            const rsi_ind = try indicators.RSI.init(allocator, self.candle_chart);
            pane_region.appendChild(&rsi_ind.indicator_region.region);
            rsi_ind.compute();
            break :b .{ .rsi = rsi_ind };
        },
        else => return,
    };
    try self.list.append(allocator, .{ .item_index = item_index, .impl = impl });
}

pub fn removeIndicator(self: *Self, allocator: std.mem.Allocator, item_index: usize) void {
    var i: usize = 0;
    while (i < self.list.items.len) {
        if (self.list.items[i].item_index == item_index) {
            var ind = self.list.orderedRemove(i);
            ind.deinit(allocator);
            break;
        } else {
            i += 1;
        }
    }
}

pub fn toggleIndicator(self: *Self, allocator: std.mem.Allocator, pane_region: *Region, item_index: usize) !void {
    const item = &ITEMS_MAP[item_index];
    if (item.is_selected) {
        self.removeIndicator(allocator, item_index);
        item.is_selected = false;
    } else {
        try self.addIndicator(allocator, pane_region, item_index);
        item.is_selected = true;
    }
}

