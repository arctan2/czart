const rl = @import("raylib");

pub const PERIOD = 20;
pub const MAX_PERIOD = 100;
pub const INDICATOR_FONT_SIZE: f32 = 16;
pub const DEFAULT_KEY_SENSITIVITY = 0.2;

pub const BADGE_FONT_SIZE: f32 = 18;
pub const BADGE_PAD_X = 18;
pub const BADGE_PAD_Y = 8;
pub const BADGE_BOTTOM_GAP = 16;
pub const BADGE_BG = rl.Color{ .r = 25, .g = 25, .b = 32, .a = 225 };
pub const BADGE_BORDER = rl.Color{ .r = 120, .g = 120, .b = 130, .a = 255 };
pub const BADGE_TEXT = rl.Color{ .r = 235, .g = 235, .b = 240, .a = 255 };

