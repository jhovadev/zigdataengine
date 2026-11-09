//! Stable scalar floating-point compositions for data processing.
//! Public functions use f64; all results are computed on the caller's CPU.
//! NaN propagates through scalar functions; bulk operations reject nonfinite inputs.
const std = @import("std");

/// Logistic sigmoid. Avoids computing exp(-x) for very negative x.
pub fn sigmoid(x: f64) f64 {
    if (x >= 0) {
        const z = @exp(-x);
        return 1.0 / (1.0 + z);
    }
    const z = @exp(x);
    return z / (1.0 + z);
}

/// log(1+exp(x)) without overflow at large positive x.
pub fn softplus(x: f64) f64 {
    if (x > 0) return x + std.math.log1p(@exp(-x));
    return std.math.log1p(@exp(x));
}

pub const BulkError = error{ EmptyInput, LengthMismatch, NonFiniteInput };

/// Stable log(sum(exp(values))), using the max-subtraction identity.
/// Rejects empty and nonfinite inputs instead of silently choosing NaN semantics.
pub fn logSumExp(values: []const f64) BulkError!f64 {
    if (values.len == 0) return error.EmptyInput;
    var max_value: f64 = -std.math.inf(f64);
    for (values) |x| {
        if (!std.math.isFinite(x)) return error.NonFiniteInput;
        max_value = @max(max_value, x);
    }
    var sum: f64 = 0;
    for (values) |x| sum += @exp(x - max_value);
    return max_value + @log(sum);
}

/// Stable softmax; supports out == values for in-place operation.
/// No output elements are written before input validation completes.
pub fn softmax(values: []const f64, out: []f64) BulkError!void {
    if (values.len == 0) return error.EmptyInput;
    if (values.len != out.len) return error.LengthMismatch;
    var max_value: f64 = -std.math.inf(f64);
    for (values) |x| {
        if (!std.math.isFinite(x)) return error.NonFiniteInput;
        max_value = @max(max_value, x);
    }
    var sum: f64 = 0;
    for (values, 0..) |x, i| {
        const e = @exp(x - max_value);
        out[i] = e;
        sum += e;
    }
    for (out) |*item| item.* /= sum;
}

test "sigmoid and softplus large magnitudes remain finite" {
    try std.testing.expectEqual(@as(f64, 1), sigmoid(1000));
    try std.testing.expectEqual(@as(f64, 0), sigmoid(-1000));
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), sigmoid(0), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 1000), softplus(1000), 1e-12);
    try std.testing.expectEqual(@as(f64, 0), softplus(-1000));
    try std.testing.expectApproxEqAbs(@as(f64, @log(2.0)), softplus(0), 1e-14);
    try std.testing.expect(std.math.isNan(sigmoid(std.math.nan(f64))));
    try std.testing.expect(std.math.isNan(softplus(std.math.nan(f64))));
}

test "log-sum-exp stable under large offsets and shift" {
    const numbers = [_]f64{ 1000, 1000 };
    const got = try logSumExp(&numbers);
    try std.testing.expectApproxEqAbs(@as(f64, 1000) + @log(@as(f64, 2)), got, 1e-12);
    const small = [_]f64{ -1000, -1001 };
    const y = try logSumExp(&small);
    try std.testing.expect(std.math.isFinite(y));
    try std.testing.expectApproxEqAbs(@as(f64, -1000) + std.math.log1p(@exp(@as(f64, -1))), y, 1e-12);
    try std.testing.expectError(error.EmptyInput, logSumExp(&.{}));
    try std.testing.expectError(error.NonFiniteInput, logSumExp(&.{ 0, std.math.inf(f64) }));
}

test "softmax normalization, in-place operation and validation" {
    const input = [_]f64{ 1000, 1001, 1002 };
    var result: [3]f64 = undefined;
    try softmax(&input, &result);
    const total = result[0] + result[1] + result[2];
    try std.testing.expectApproxEqAbs(@as(f64, 1), total, 1e-14);
    try std.testing.expect(result[2] > result[1] and result[1] > result[0]);
    var inplace = input;
    try softmax(&inplace, &inplace);
    for (result, inplace) |want, have| try std.testing.expectApproxEqAbs(want, have, 1e-15);
    var untouched = [_]f64{ 91, 92 };
    try std.testing.expectError(error.NonFiniteInput, softmax(&.{ 1, std.math.nan(f64) }, &untouched));
    try std.testing.expectEqual(@as(f64, 91), untouched[0]);
    try std.testing.expectError(error.LengthMismatch, softmax(&input, &untouched));
}
