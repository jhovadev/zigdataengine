//! High-precision f128 two-pass references for accuracy regression tests.
//! We do not claim that f128 is a correctly rounded arbitrary-precision oracle.
const std = @import("std");
const moments = @import("../compute/moments.zig");
const sum_mod = @import("../compute/sum.zig");
const precision = @import("precision.zig");

const Reference = struct { mean: f128, variance: f128 };
fn reference(values: []const f64) Reference {
    var total: f128 = 0;
    for (values) |value| total += @as(f128, value);
    const denom: f128 = @floatFromInt(values.len);
    const mean = total / denom;
    var squares: f128 = 0;
    for (values) |value| {
        const delta = @as(f128, value) - mean;
        squares += delta * delta;
    }
    return .{ .mean = mean, .variance = squares / denom };
}

test "Welford and Chan accuracy against f128 two-pass reference" {
    const samples = [_]f64{
        1_000_000_001.0, 1_000_000_002.0, 1_000_000_003.0,
        1_000_000_004.0, 1_000_000_005.0, 1_000_000_006.0,
        1_000_000_007.0, 1_000_000_008.0,
    };
    const want = reference(&samples);
    var one: moments.Moments = .{};
    var left: moments.Moments = .{};
    var right: moments.Moments = .{};
    for (samples, 0..) |value, i| {
        try one.update(value);
        if (i < 4) try left.update(value) else try right.update(value);
    }
    try left.merge(right);
    const mean: f64 = @floatCast(want.mean);
    const variance: f64 = @floatCast(want.variance);
    try std.testing.expect(precision.almostEqual(one.mean, mean, 1e-6, 1e-14));
    try std.testing.expect(precision.almostEqual(one.populationVariance().?, variance, 1e-6, 1e-8));
    try std.testing.expect(precision.almostEqual(left.mean, mean, 1e-6, 1e-14));
    try std.testing.expect(precision.almostEqual(left.populationVariance().?, variance, 1e-6, 1e-8));
}

test "compensated summation retains low-order term relative to f128" {
    const xs = [_]f64{ 1e16, 1.0, -1e16, 2.0 };
    var expected: f128 = 0;
    var actual: sum_mod.CompensatedSum = .{};
    for (xs) |value| {
        expected += @as(f128, value);
        try actual.update(value);
    }
    try std.testing.expectEqual(@as(f64, @floatCast(expected)), actual.finish());
}
