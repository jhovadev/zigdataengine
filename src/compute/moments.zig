//! Online mean/variance using Welford updates and Chan's pairwise merge.
//! Caller controls update order and merge tree. No allocation or I/O.
const std = @import("std");

pub const Error = error{ NonFiniteInput, CountOverflow, NonFiniteResult };

pub const Moments = struct {
    count: u64 = 0,
    mean: f64 = 0,
    m2: f64 = 0,

    /// One sample per update. Does not accept NaN or infinity.
    pub fn update(self: *Moments, value: f64) Error!void {
        if (!std.math.isFinite(value)) return error.NonFiniteInput;
        const sum = @addWithOverflow(self.count, @as(u64, 1));
        if (sum[1] != 0) return error.CountOverflow;
        const next_count = sum[0];
        const delta = value - self.mean;
        const next_mean = self.mean + delta / @as(f64, @floatFromInt(next_count));
        const next_m2 = self.m2 + delta * (value - next_mean);
        if (!std.math.isFinite(next_mean) or !std.math.isFinite(next_m2)) return error.NonFiniteResult;
        self.count = next_count;
        self.mean = next_mean;
        self.m2 = next_m2;
    }

    /// Merge independent accumulators; input order is the caller's responsibility.
    /// For reproducible parallel results, merge in a deterministic fixed tree.
    pub fn merge(self: *Moments, other: Moments) Error!void {
        if (other.count == 0) return;
        if (self.count == 0) {
            self.* = other;
            return;
        }
        const sum = @addWithOverflow(self.count, other.count);
        if (sum[1] != 0) return error.CountOverflow;
        const total = sum[0];
        const a: f64 = @floatFromInt(self.count);
        const b: f64 = @floatFromInt(other.count);
        const n: f64 = @floatFromInt(total);
        const delta = other.mean - self.mean;
        const new_mean = self.mean + delta * (b / n);
        const new_m2 = self.m2 + other.m2 + delta * delta * (a / n) * b;
        if (!std.math.isFinite(new_mean) or !std.math.isFinite(new_m2)) return error.NonFiniteResult;
        self.count = total;
        self.mean = new_mean;
        self.m2 = new_m2;
    }

    pub fn populationVariance(self: Moments) ?f64 {
        if (self.count == 0) return null;
        return self.m2 / @as(f64, @floatFromInt(self.count));
    }

    pub fn sampleVariance(self: Moments) ?f64 {
        if (self.count < 2) return null;
        return self.m2 / @as(f64, @floatFromInt(self.count - 1));
    }

    pub fn average(self: Moments) ?f64 {
        return if (self.count == 0) null else self.mean;
    }

    /// Uniform, allocation-free snapshot for composable streaming consumers.
    pub fn finish(self: Moments) Summary {
        return .{
            .count = self.count,
            .mean = self.average(),
            .population_variance = self.populationVariance(),
            .sample_variance = self.sampleVariance(),
        };
    }

    pub const Summary = struct {
        count: u64,
        mean: ?f64,
        population_variance: ?f64,
        sample_variance: ?f64,
    };
};

test "empty and singleton moments" {
    var m: Moments = .{};
    try std.testing.expect(m.average() == null);
    try std.testing.expect(m.populationVariance() == null);
    try std.testing.expect(m.sampleVariance() == null);
    try m.update(7.0);
    try std.testing.expectEqual(@as(u64, 1), m.count);
    try std.testing.expectEqual(@as(f64, 7.0), m.average().?);
    try std.testing.expectEqual(@as(f64, 0), m.populationVariance().?);
    try std.testing.expect(m.sampleVariance() == null);
}

test "online Welford and merge Chan match reference" {
    const data = [_]f64{ 1, 2, 3, 4, 5, 6 };
    var whole: Moments = .{};
    var left: Moments = .{};
    var right: Moments = .{};
    for (data, 0..) |x, i| {
        try whole.update(x);
        if (i < 3) try left.update(x) else try right.update(x);
    }
    try left.merge(right);
    try std.testing.expectEqual(@as(u64, 6), left.count);
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), whole.mean, 1e-12);
    try std.testing.expectApproxEqAbs(whole.mean, left.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 35.0 / 12.0), left.populationVariance().?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), left.sampleVariance().?, 1e-12);
}

test "large offset and non-finite sample rejection without state mutation" {
    var m: Moments = .{};
    const base = 1_000_000_000.0;
    for ([_]f64{ base + 1, base + 2, base + 3, base + 4 }) |x| try m.update(x);
    try std.testing.expectApproxEqAbs(base + 2.5, m.mean, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 1.25), m.populationVariance().?, 1e-6);
    const old = m;
    try std.testing.expectError(error.NonFiniteInput, m.update(std.math.nan(f64)));
    try std.testing.expectError(error.NonFiniteInput, m.update(std.math.inf(f64)));
    try std.testing.expectEqual(old.count, m.count);
    try std.testing.expectEqual(old.mean, m.mean);
}

test "merging empty accumulator is identity" {
    var a: Moments = .{};
    var b: Moments = .{};
    try b.update(10);
    try a.merge(b);
    try a.merge(.{});
    try std.testing.expectEqual(@as(u64, 1), a.count);
    try std.testing.expectEqual(@as(f64, 10), a.mean);
}

test "finish exposes nullable summary without allocating" {
    var m: Moments = .{};
    const empty = m.finish();
    try std.testing.expectEqual(@as(u64, 0), empty.count);
    try std.testing.expect(empty.mean == null);
    try m.update(2);
    try m.update(4);
    const result = m.finish();
    try std.testing.expectEqual(@as(u64, 2), result.count);
    try std.testing.expectEqual(@as(f64, 3), result.mean.?);
    try std.testing.expectEqual(@as(f64, 1), result.population_variance.?);
}
