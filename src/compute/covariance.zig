//! Streaming bivariate moments: covariance and Pearson correlation.
//! Welford-style updates and Chan-style merges; no allocation or I/O.
//! Merge order influences final rounding; callers choose their merge tree.
const std = @import("std");

pub const Error = error{ NonFiniteInput, CountOverflow, NonFiniteResult };

pub const Covariance = struct {
    count: u64 = 0,
    mean_x: f64 = 0,
    mean_y: f64 = 0,
    m2_x: f64 = 0,
    m2_y: f64 = 0,
    c2: f64 = 0,

    pub fn update(self: *Covariance, x: f64, y: f64) Error!void {
        if (!std.math.isFinite(x) or !std.math.isFinite(y)) return error.NonFiniteInput;
        const next = @addWithOverflow(self.count, @as(u64, 1));
        if (next[1] != 0) return error.CountOverflow;
        const n: f64 = @floatFromInt(next[0]);
        const dx = x - self.mean_x;
        const dy = y - self.mean_y;
        const mx = self.mean_x + dx / n;
        const my = self.mean_y + dy / n;
        const x2 = self.m2_x + dx * (x - mx);
        const y2 = self.m2_y + dy * (y - my);
        const cross = self.c2 + dx * (y - my);
        if (!std.math.isFinite(mx) or !std.math.isFinite(my) or
            !std.math.isFinite(x2) or !std.math.isFinite(y2) or !std.math.isFinite(cross))
            return error.NonFiniteResult;
        self.* = .{ .count = next[0], .mean_x = mx, .mean_y = my,
            .m2_x = x2, .m2_y = y2, .c2 = cross };
    }

    pub fn merge(self: *Covariance, other: Covariance) Error!void {
        if (other.count == 0) return;
        if (self.count == 0) {
            self.* = other;
            return;
        }
        const next = @addWithOverflow(self.count, other.count);
        if (next[1] != 0) return error.CountOverflow;
        const a: f64 = @floatFromInt(self.count);
        const b: f64 = @floatFromInt(other.count);
        const n: f64 = @floatFromInt(next[0]);
        const dx = other.mean_x - self.mean_x;
        const dy = other.mean_y - self.mean_y;
        const weight = (a / n) * b;
        const mx = self.mean_x + dx * (b / n);
        const my = self.mean_y + dy * (b / n);
        const xx = self.m2_x + other.m2_x + dx * dx * weight;
        const yy = self.m2_y + other.m2_y + dy * dy * weight;
        const xy = self.c2 + other.c2 + dx * dy * weight;
        if (!std.math.isFinite(mx) or !std.math.isFinite(my) or
            !std.math.isFinite(xx) or !std.math.isFinite(yy) or !std.math.isFinite(xy))
            return error.NonFiniteResult;
        self.* = .{ .count = next[0], .mean_x = mx, .mean_y = my,
            .m2_x = xx, .m2_y = yy, .c2 = xy };
    }

    pub fn populationCovariance(self: Covariance) ?f64 {
        if (self.count == 0) return null;
        return self.c2 / @as(f64, @floatFromInt(self.count));
    }

    pub fn sampleCovariance(self: Covariance) ?f64 {
        if (self.count < 2) return null;
        return self.c2 / @as(f64, @floatFromInt(self.count - 1));
    }

    /// Null for insufficient samples or constant/degenerate columns.
    /// Scales factors first to avoid unnecessary product overflow.
    pub fn correlation(self: Covariance) ?f64 {
        if (self.count < 2 or self.m2_x <= 0 or self.m2_y <= 0) return null;
        const sx = @sqrt(self.m2_x);
        const sy = @sqrt(self.m2_y);
        if (sx == 0 or sy == 0) return null;
        const r = (self.c2 / sx) / sy;
        if (!std.math.isFinite(r)) return null;
        return @max(-1.0, @min(1.0, r));
    }
};

test "linear and inverse correlation; nullable empty/constant" {
    var p: Covariance = .{};
    try std.testing.expect(p.populationCovariance() == null);
    try std.testing.expect(p.correlation() == null);
    for ([_]f64{ 1, 2, 3 }) |x| try p.update(x, 2 * x);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 / 3.0), p.populationCovariance().?, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 2), p.sampleCovariance().?, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1), p.correlation().?, 1e-14);
    var inv: Covariance = .{};
    for ([_]f64{ 1, 2, 3 }) |x| try inv.update(x, 4 - x);
    try std.testing.expectApproxEqAbs(@as(f64, -1), inv.correlation().?, 1e-14);
    var flat: Covariance = .{};
    try flat.update(1, 5);
    try flat.update(2, 5);
    try std.testing.expect(flat.correlation() == null);
}

test "covariance independent partitions merge to reference" {
    var full: Covariance = .{};
    var left: Covariance = .{};
    var right: Covariance = .{};
    const xs = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const ys = [_]f64{ 3, 2, 7, 4, 11, 6, 15, 8 };
    for (xs, ys, 0..) |x, y, i| {
        try full.update(x, y);
        if (i < 4) try left.update(x, y) else try right.update(x, y);
    }
    try left.merge(right);
    try std.testing.expectEqual(full.count, left.count);
    try std.testing.expectApproxEqAbs(full.c2, left.c2, 1e-12);
    try std.testing.expectApproxEqAbs(full.correlation().?, left.correlation().?, 1e-12);
    // Independent f128 two-pass oracle, computed from the input pairs.
    var xm: f128 = 0;
    var ym: f128 = 0;
    for (xs, ys) |x, y| {
        xm += @as(f128, x);
        ym += @as(f128, y);
    }
    xm /= @as(f128, @floatFromInt(xs.len));
    ym /= @as(f128, @floatFromInt(ys.len));
    var ref_cross: f128 = 0;
    for (xs, ys) |x, y| ref_cross += (@as(f128, x) - xm) * (@as(f128, y) - ym);
    try std.testing.expectApproxEqAbs(@as(f64, @floatCast(ref_cross / @as(f128, @floatFromInt(xs.len)))), full.populationCovariance().?, 1e-12);
}

test "covariance rejects nonfinite samples and overflow atomically" {
    var p: Covariance = .{};
    try p.update(1, 2);
    const before = p;
    try std.testing.expectError(error.NonFiniteInput, p.update(std.math.nan(f64), 1));
    try std.testing.expectError(error.NonFiniteInput, p.update(1, std.math.inf(f64)));
    try std.testing.expectEqual(before.count, p.count);
    try std.testing.expectEqual(before.c2, p.c2);
    var huge: Covariance = .{ .count = std.math.maxInt(u64) };
    try std.testing.expectError(error.CountOverflow, huge.update(0, 0));
    try std.testing.expectEqual(std.math.maxInt(u64), huge.count);
}
