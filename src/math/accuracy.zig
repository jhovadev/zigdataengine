//! Lightweight f64 accuracy report for reference-vector validation.
//! A report is not a formal proof of correct rounding on every platform.
const std = @import("std");
const precision = @import("precision.zig");

pub const Kind = enum { finite, same_infinity, both_nan, mismatch };
pub const Report = struct {
    kind: Kind,
    absolute_error: ?f64 = null,
    relative_error: ?f64 = null,
    ulps: ?u64 = null,

    /// Evaluate an explicit ULP threshold for finite numbers only.
    pub fn withinUlps(self: Report, bound: u64) bool {
        return switch (self.kind) {
            .finite => self.ulps.? <= bound,
            .same_infinity, .both_nan => true,
            .mismatch => false,
        };
    }
};

pub fn compare(actual: f64, expected: f64) Report {
    if (std.math.isNan(actual) or std.math.isNan(expected))
        return .{ .kind = if (std.math.isNan(actual) and std.math.isNan(expected)) .both_nan else .mismatch };
    if (!std.math.isFinite(actual) or !std.math.isFinite(expected))
        return .{ .kind = if (actual == expected) .same_infinity else .mismatch };
    const absolute = @abs(actual - expected);
    return .{
        .kind = .finite,
        .absolute_error = absolute,
        .relative_error = if (expected == 0) null else absolute / @abs(expected),
        .ulps = precision.ulpDistance(actual, expected).?,
    };
}

test "accuracy handles signed zeros, infinities, NaN and mismatch" {
    try std.testing.expectEqual(@as(u64, 0), compare(-0.0, 0.0).ulps.?);
    try std.testing.expect(compare(std.math.inf(f64), std.math.inf(f64)).withinUlps(0));
    try std.testing.expect(compare(std.math.nan(f64), std.math.nan(f64)).withinUlps(0));
    try std.testing.expect(!compare(std.math.nan(f64), 1).withinUlps(100));
    try std.testing.expect(!compare(-std.math.inf(f64), std.math.inf(f64)).withinUlps(100));
    const after_one: f64 = @bitCast(@as(u64, 0x3ff0000000000001));
    try std.testing.expectEqual(@as(u64, 1), compare(after_one, 1).ulps.?);
}
