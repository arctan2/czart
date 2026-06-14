const std = @import("std");

pub fn niceInterval(raw: f32) f32 {
    if (raw <= 0) return 1;
    const magnitude = std.math.pow(f32, 10.0, @floor(std.math.log10(raw)));
    const normalized = raw / magnitude;
    const nice: f32 = if (normalized < 1.5) 1.0 else if (normalized < 3.5) 2.0 else if (normalized < 7.5) 5.0 else 10.0;
    return nice * magnitude;
}

pub const MonthNames = [_][]const u8{
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

pub const DateFormatter = struct {
    allocator: std.mem.Allocator,

    pub fn toNumericDash(self: *const DateFormatter, epoch_seconds: i64) ![]u8 {
        const epoch_days = @divFloor(epoch_seconds, std.time.epoch.secs_per_day);
        const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_days) };
        const year_and_day = epoch_day.calculateYearDay()();
        const month_and_day = year_and_day.calculateMonthAndDay();

        return try std.fmt.allocPrint(self.allocator, "{d:0>2}-{d:0>2}-{d:0>4}", .{
            month_and_day.day_index + 1,
            month_and_day.month.numeric(),
            year_and_day.year,
        });
    }

    pub fn toTextual(self: *const DateFormatter, epoch_seconds: i64) ![]u8 {
        const epoch_days = @divFloor(epoch_seconds, std.time.epoch.secs_per_day);
        const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_days) };
        const year_and_day = epoch_day.calculateYearDay();
        const month_and_day = year_and_day.calculateMonthDay();

        const month_idx = month_and_day.month.numeric() - 1;

        return try std.fmt.allocPrint(self.allocator, "{s} {d}, {d}", .{
            MonthNames[month_idx],
            month_and_day.day_index + 1,
            year_and_day.year,
        });
    }

    pub fn toTextualTime(self: *const DateFormatter, epoch_seconds: i64) ![]u8 {
        const secs_per_day: i64 = std.time.epoch.secs_per_day;
        const epoch_days = @divFloor(epoch_seconds, secs_per_day);
        const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_days) };
        const year_and_day = epoch_day.calculateYearDay();
        const month_and_day = year_and_day.calculateMonthDay();
        const month_idx = month_and_day.month.numeric() - 1;

        var secs_of_day = @mod(epoch_seconds, secs_per_day);
        if (secs_of_day < 0) secs_of_day += secs_per_day;

        const hours: u64 = @intCast(@divFloor(secs_of_day, 3600));
        const minutes: u64 = @intCast(@divFloor(@mod(secs_of_day, 3600), 60));

        return try std.fmt.allocPrint(self.allocator, "{s} {d} {d:0>2}:{d:0>2}", .{
            MonthNames[month_idx],
            month_and_day.day_index + 1,
            hours,
            minutes,
        });
    }
};

pub const Timeframe = enum {
    m1,
    m5,
    m30,
    h1,
    d1,
    d7,

    pub fn getMsDelta(self: Timeframe) f32 {
        return switch (self) {
            .m1 => 60_000.0,
            .m5 => 300_000.0,
            .m30 => 1_800_000.0,
            .h1 => 3_600_000.0,
            .d1 => 86_400_000.0,
            .d7 => 604_800_000.0,
        };
    }

    pub fn showsTime(self: Timeframe) bool {
        return switch (self) {
            .m1, .m5, .m30, .h1 => true,
            .d1, .d7 => false,
        };
    }
};

pub const MinMax = struct {
    min: f32,
    max: f32,

    pub fn pad(self: *MinMax, factor: f32) void {
        const p = (self.max - self.min) * factor;
        self.max += p;
        self.min -= p;
    }

    pub inline fn range(self: *const MinMax) f32 {
        return self.max - self.min;
    }
};

pub const MinMaxYX = struct {
    y: MinMax,
    x: MinMax
};
