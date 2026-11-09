//! Fixed binary reduction tree for an order-stable sum of finite f64 values.
//! No allocations, no runtime, no hidden parallelism. The shape depends only
//! on the input length, not on caller chunking or worker count.
//! Bit-identical results are NOT promised across targets or compiler modes.
const std = @import("std");
const CompensatedSum = @import("sum.zig").CompensatedSum;

fn reduce(values: []const f64) error{ NonFiniteInput, NonFiniteResult }!CompensatedSum {
    if (values.len <= 1) {
        var leaf: CompensatedSum = .{};
        if (values.len == 1) try leaf.update(values[0]);
        return leaf;
    }
    const mid = values.len / 2;
    var left = try reduce(values[0..mid]);
    const right = try reduce(values[mid..]);
    try left.merge(right);
    return left;
}

/// Deterministic shape, with compensating terms retained across tree merges.
/// Empty input returns zero; rejects NaN and infinities.
pub fn sumFixedTree(values: []const f64) error{ NonFiniteInput, NonFiniteResult }!f64 {
    return (try reduce(values)).finish();
}

test "fixed tree preserves small summands and is repeatable" {
    const xs = [_]f64{ 1e16, 1, -1e16, 2, -3, 4 };
    const expected: f64 = 4;
    const first = try sumFixedTree(&xs);
    try std.testing.expectEqual(expected, first);
    for (0..10) |_| try std.testing.expectEqual(first, try sumFixedTree(&xs));
    try std.testing.expectEqual(@as(f64, 0), try sumFixedTree(&.{}));
    try std.testing.expectError(error.NonFiniteInput, sumFixedTree(&.{ 1, std.math.nan(f64) }));
}
