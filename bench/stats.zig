//! Tiny deterministic statistics harness for performance measurements.
//! Percentiles use the nearest-rank definition; no external dependency.
const std = @import("std");

pub const Summary = struct {
    minimum_ns: u64,
    median_ns: u64,
    p95_ns: u64,
    maximum_ns: u64,
};

/// Sorts the passed samples in-place. The caller must retain its original
/// samples separately if their chronological order matters.
pub fn summarize(samples: []u64) !Summary {
    if (samples.len == 0) return error.NoSamples;
    // Insertion sort is more than sufficient for the default 30 repetitions,
    // and avoids relying on sorting APIs that change across Zig versions.
    for (1..samples.len) |i| {
        const value = samples[i];
        var j = i;
        while (j > 0 and samples[j - 1] > value) : (j -= 1) {
            samples[j] = samples[j - 1];
        }
        samples[j] = value;
    }
    const n = samples.len;
    const median = if (n % 2 == 1)
        samples[n / 2]
    else
        @as(u64, @intCast((@as(u128, samples[n / 2 - 1]) + samples[n / 2]) / 2));
    // ceil(0.95*n)-1, with a nonzero length and n capped by the CLI.
    const p95_index = (95 * n + 99) / 100 - 1;
    return .{
        .minimum_ns = samples[0],
        .median_ns = median,
        .p95_ns = samples[p95_index],
        .maximum_ns = samples[n - 1],
    };
}

pub fn mibPerSecond(byte_count: usize, ns: u64) f64 {
    if (ns == 0) return 0;
    const seconds = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
    return (@as(f64, @floatFromInt(byte_count)) / 1_048_576.0) / seconds;
}

test "nearest-rank p95 and even median" {
    var values = [_]u64{ 6, 1, 5, 3, 2, 4 };
    const s = try summarize(&values);
    try std.testing.expectEqual(@as(u64, 1), s.minimum_ns);
    try std.testing.expectEqual(@as(u64, 3), s.median_ns);
    try std.testing.expectEqual(@as(u64, 6), s.p95_ns);
    try std.testing.expectEqual(@as(u64, 6), s.maximum_ns);
}

test "single value, odd values, and empty input" {
    var single = [_]u64{9};
    const one = try summarize(&single);
    try std.testing.expectEqual(@as(u64, 9), one.median_ns);
    var odd = [_]u64{ 9, 3, 5 };
    const three = try summarize(&odd);
    try std.testing.expectEqual(@as(u64, 5), three.median_ns);
    var empty = [_]u64{};
    try std.testing.expectError(error.NoSamples, summarize(&empty));
    try std.testing.expectEqual(@as(f64, 0), mibPerSecond(1024, 0));
}
