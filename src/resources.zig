const rl = @import("raylib");
const Self = @This();

pub const CHART_BG: rl.Color = .{ .r = 20, .g = 20, .b = 25, .a = 255 };
pub const GRID_COLOR: rl.Color = .{ .r = 50, .g = 50, .b = 50, .a = 255 };
pub const AXIS_BG: rl.Color = .{ .r = 30, .g = 20, .b = 30, .a = 255 };
pub const AXIS_BORDER_COLOR: rl.Color = .{ .r = 160, .g = 60, .b = 160, .a = 255 };

font: rl.Font,

pub fn init() !Self {
    const font = try rl.loadFont("/Users/prateek/Library/Fonts/HackNerdFontMono-Bold.ttf");
    return .{
        .font = font
    };
}

pub fn measureText(self: *const Self, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2 {
    return rl.measureTextEx(self.font, text, font_size, spacing);
}
