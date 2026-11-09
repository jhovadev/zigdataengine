//! Fixed-width bounds for std.testing.Smith (Zig 0.17).
//! `usize` is target-dependent and is not accepted as a Smith value type.
const std = @import("std");

pub fn boundedLen(smith: *std.testing.Smith, max: u32) usize {
    return @intCast(smith.valueRangeAtMost(u32, 0, max));
}
