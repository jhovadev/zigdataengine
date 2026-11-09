//! Numerical comparison helpers intended for tests and result validation.
const std = @import("std");

fn orderedBits(value: f64) u64 {
    const bits: u64 = @bitCast(value);
    const sign: u64 = @as(u64, 1) << 63;
    return if ((bits & sign) != 0) ~bits else bits | sign;
}

/// Returns the number of representable f64 steps between inputs; null for NaN.
/// -0 and +0 are treated as equal. Same-sign infinities have distance zero.
pub fn ulpDistance(a: f64, b: f64) ?u64 {
    if (std.math.isNan(a) or std.math.isNan(b)) return null;
    if (a == b) return 0;
    const ia = orderedBits(a);
    const ib = orderedBits(b);
    return if (ia >= ib) ia - ib else ib - ia;
}

/// Absolute-plus-relative tolerance check, with explicit nonfinite semantics.
/// Negative/NaN/infinite tolerances are rejected.
pub fn almostEqual(a: f64, b: f64, abs_tol: f64, rel_tol: f64) bool {
    if (!std.math.isFinite(abs_tol) or !std.math.isFinite(rel_tol) or abs_tol < 0 or rel_tol < 0)
        return false;
    if (std.math.isNan(a) or std.math.isNan(b)) return false;
    if (a == b) return true;
    if (!std.math.isFinite(a) or !std.math.isFinite(b)) return false;
    const tolerance = @max(abs_tol, rel_tol * @max(@abs(a), @abs(b)));
    return @abs(a - b) <= tolerance;
}

test "ULP distance handles adjacent values and special cases" {
    const one = @as(f64, 1.0);
    const after_one: f64 = @bitCast(@as(u64, 0x3ff0000000000001));
    try std.testing.expectEqual(@as(u64, 1), ulpDistance(one, after_one).?);
    try std.testing.expectEqual(@as(u64, 0), ulpDistance(0.0, -0.0).?);
    try std.testing.expectEqual(@as(u64, 0), ulpDistance(std.math.inf(f64), std.math.inf(f64)).?);
    try std.testing.expect(ulpDistance(std.math.nan(f64), one) == null);
}

test "almost equal uses both tolerances and rejects NaN" {
    try std.testing.expect(almostEqual(1.0, 1.0 + 1e-10, 0, 1e-9));
    try std.testing.expect(almostEqual(0.0, 1e-12, 1e-11, 0));
    try std.testing.expect(!almostEqual(0.0, 1e-4, 1e-6, 1e-6));
    try std.testing.expect(!almostEqual(std.math.nan(f64), 1, 1, 1));
    try std.testing.expect(!almostEqual(1, 1, -1, 0));
    try std.testing.expect(almostEqual(std.math.inf(f64), std.math.inf(f64), 0, 0));
    try std.testing.expect(!almostEqual(std.math.inf(f64), -std.math.inf(f64), 0, 0));
}
