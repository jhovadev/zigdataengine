//! Neumaier compensated sum. Does not promise exact rounding or cross-target
//! bit-identical results. Values must be finite.
const std = @import("std");

pub const CompensatedSum = struct {
    sum: f64 = 0,
    correction: f64 = 0,

    pub fn update(self: *CompensatedSum, x: f64) error{ NonFiniteInput, NonFiniteResult }!void {
        if (!std.math.isFinite(x)) return error.NonFiniteInput;
        const t = self.sum + x;
        const correction = self.correction + if (@abs(self.sum) >= @abs(x))
            (self.sum - t) + x
        else
            (x - t) + self.sum;
        if (!std.math.isFinite(t) or !std.math.isFinite(correction)) return error.NonFiniteResult;
        self.sum = t;
        self.correction = correction;
    }

    pub fn merge(self: *CompensatedSum, other: CompensatedSum) error{ NonFiniteInput, NonFiniteResult }!void {
        // Preserve both pieces rather than rounding to other.finish first.
        try self.update(other.sum);
        try self.update(other.correction);
    }

    pub fn finish(self: CompensatedSum) f64 {
        return self.sum + self.correction;
    }
};

test "compensation recovers a low-order term" {
    var sum: CompensatedSum = .{};
    for ([_]f64{ 1e16, 1, -1e16 }) |x| try sum.update(x);
    try std.testing.expectEqual(@as(f64, 1), sum.finish());
}

test "merge and input validation" {
    var left: CompensatedSum = .{};
    var right: CompensatedSum = .{};
    try left.update(1e16);
    try right.update(1);
    try right.update(-1e16);
    try left.merge(right);
    try std.testing.expectEqual(@as(f64, 1), left.finish());
    const before = left.finish();
    try std.testing.expectError(error.NonFiniteInput, left.update(std.math.nan(f64)));
    try std.testing.expectEqual(before, left.finish());
}
