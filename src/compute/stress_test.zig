//! M1.9 merge-order and partition-size regression tests against f128 two-pass
//! independent references. Floating-point merge results need not be bit-identical.
const std = @import("std");
const Moments = @import("moments.zig").Moments;
const Covariance = @import("covariance.zig").Covariance;
const CompensatedSum = @import("sum.zig").CompensatedSum;
const fixed = @import("deterministic.zig");

const N = 256;
const Data = struct { x: [N]f64, y: [N]f64 };
const Oracle = struct {
    mean_x: f64,
    variance_x: f64,
    covariance: f64,
    correlation: f64,
    sum_x: f64,
};

fn makeData() Data {
    var data: Data = undefined;
    for (0..N) |i| {
        const ax: i64 = @intCast((i * 73 + 19) % 233);
        const ay: i64 = @intCast((i * 149 + 37) % 191);
        // Exact binary fractions keep the independent oracle meaningful.
        data.x[i] = 1_000_000.0 + @as(f64, @floatFromInt(ax - 116)) / 32.0;
        data.y[i] = -400_000.0 + @as(f64, @floatFromInt(ay - 95)) / 64.0;
    }
    return data;
}

fn oracle(data: Data) Oracle {
    var sum_x: f128 = 0;
    var sum_y: f128 = 0;
    for (data.x, data.y) |x, y| {
        sum_x += @as(f128, x);
        sum_y += @as(f128, y);
    }
    const denom: f128 = @floatFromInt(N);
    const mx = sum_x / denom;
    const my = sum_y / denom;
    var xx: f128 = 0;
    var yy: f128 = 0;
    var xy: f128 = 0;
    for (data.x, data.y) |x, y| {
        const dx = @as(f128, x) - mx;
        const dy = @as(f128, y) - my;
        xx += dx * dx;
        yy += dy * dy;
        xy += dx * dy;
    }
    return .{
        .mean_x = @floatCast(mx),
        .variance_x = @floatCast(xx / denom),
        .covariance = @floatCast(xy / denom),
        .correlation = @floatCast(xy / @sqrt(xx * yy)),
        .sum_x = @floatCast(sum_x),
    };
}

fn check(m: Moments, c: Covariance, sum: CompensatedSum, expected: Oracle) !void {
    try std.testing.expectEqual(@as(u64, N), m.count);
    try std.testing.expectEqual(@as(u64, N), c.count);
    // Tolerances cover expected reordering error, not unlimited inaccuracy.
    try std.testing.expectApproxEqAbs(expected.mean_x, m.mean, 1e-6);
    try std.testing.expectApproxEqAbs(expected.variance_x, m.populationVariance().?, 1e-6);
    try std.testing.expectApproxEqAbs(expected.covariance, c.populationCovariance().?, 1e-6);
    try std.testing.expectApproxEqAbs(expected.correlation, c.correlation().?, 1e-6);
    try std.testing.expectApproxEqAbs(expected.sum_x, sum.finish(), 1e-6);
}

fn runPartitions(data: Data, span: usize, reverse: bool, expected: Oracle) !void {
    var parts_m: [N]Moments = undefined;
    var parts_c: [N]Covariance = undefined;
    var parts_s: [N]CompensatedSum = undefined;
    var count: usize = 0;
    var begin: usize = 0;
    while (begin < N) : (begin += span) {
        const end = @min(N, begin + span);
        var m: Moments = .{};
        var c: Covariance = .{};
        var sum: CompensatedSum = .{};
        for (begin..end) |i| {
            try m.update(data.x[i]);
            try c.update(data.x[i], data.y[i]);
            try sum.update(data.x[i]);
        }
        parts_m[count] = m;
        parts_c[count] = c;
        parts_s[count] = sum;
        count += 1;
    }
    var merged_m: Moments = .{};
    var merged_c: Covariance = .{};
    var merged_s: CompensatedSum = .{};
    for (0..count) |k| {
        const i = if (reverse) count - k - 1 else k;
        try merged_m.merge(parts_m[i]);
        try merged_c.merge(parts_c[i]);
        try merged_s.merge(parts_s[i]);
    }
    try check(merged_m, merged_c, merged_s, expected);
}

test "f128 reference: Welford, Chan, bivariate merges over multiple partition sizes and orders" {
    const data = makeData();
    const expected = oracle(data);
    for ([_]usize{ 1, 2, 3, 7, 16, 31, 64, 128, 256 }) |size| {
        try runPartitions(data, size, false, expected);
        try runPartitions(data, size, true, expected);
    }
}

test "fixed summation tree returns same f64 bits on repeated runs" {
    const data = makeData();
    const first = try fixed.sumFixedTree(&data.x);
    for (0..16) |_| {
        const result = try fixed.sumFixedTree(&data.x);
        try std.testing.expectEqual(@as(u64, @bitCast(first)), @as(u64, @bitCast(result)));
    }
    try std.testing.expectApproxEqAbs(oracle(data).sum_x, first, 1e-6);
}

fn checkSame(a: Moments, b: Moments, x: Covariance, y: Covariance) !void {
    try std.testing.expectEqual(@as(u64, @bitCast(a.mean)), @as(u64, @bitCast(b.mean)));
    try std.testing.expectEqual(@as(u64, @bitCast(a.m2)), @as(u64, @bitCast(b.m2)));
    try std.testing.expectEqual(@as(u64, @bitCast(x.c2)), @as(u64, @bitCast(y.c2)));
}

test "same fixed merge tree gives identical representation within one executable" {
    const data = makeData();
    var lhs_m: [8]Moments = undefined;
    var lhs_c: [8]Covariance = undefined;
    for (0..8) |p| {
        var m: Moments = .{};
        var c: Covariance = .{};
        for (p * 32..(p + 1) * 32) |i| {
            try m.update(data.x[i]);
            try c.update(data.x[i], data.y[i]);
        }
        lhs_m[p] = m;
        lhs_c[p] = c;
    }
    var rhs_m = lhs_m;
    var rhs_c = lhs_c;
    var count: usize = 8;
    while (count > 1) {
        for (0..count / 2) |i| {
            try lhs_m[i * 2].merge(lhs_m[i * 2 + 1]);
            try lhs_c[i * 2].merge(lhs_c[i * 2 + 1]);
            try rhs_m[i * 2].merge(rhs_m[i * 2 + 1]);
            try rhs_c[i * 2].merge(rhs_c[i * 2 + 1]);
            lhs_m[i] = lhs_m[i * 2];
            lhs_c[i] = lhs_c[i * 2];
            rhs_m[i] = rhs_m[i * 2];
            rhs_c[i] = rhs_c[i * 2];
        }
        count /= 2;
    }
    try checkSame(lhs_m[0], rhs_m[0], lhs_c[0], rhs_c[0]);
    try std.testing.expectApproxEqAbs(oracle(data).variance_x, lhs_m[0].populationVariance().?, 1e-6);
}
