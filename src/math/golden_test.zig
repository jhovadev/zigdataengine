//! Hermetic test vectors generated independently with mpmath at 100 dps.
//! Tests run with Zig alone, no Python dependency at runtime.
const std = @import("std");
const golden = @import("golden.zig");
const stable = @import("stable.zig");
const accuracy = @import("accuracy.zig");

// Allow a bounded implementation-specific rounding difference; anything above
// the threshold must be diagnosed against an updated high-precision oracle.
const max_ulps: u64 = 16;

test "sigmoid and softplus against 100-digit golden vectors" {
    for (golden.unary) |entry| {
        const x: f64 = @bitCast(entry.x_bits);
        const expected_s: f64 = @bitCast(entry.sigmoid_bits);
        const expected_p: f64 = @bitCast(entry.softplus_bits);
        try std.testing.expect(accuracy.compare(stable.sigmoid(x), expected_s).withinUlps(max_ulps));
        try std.testing.expect(accuracy.compare(stable.softplus(x), expected_p).withinUlps(max_ulps));
    }
}

test "logSumExp and softmax against 100-digit golden vectors" {
    for (golden.vectors) |entry| {
        var input: [4]f64 = undefined;
        for (entry.inputs, 0..) |word, i| input[i] = @bitCast(word);
        const expected_lse: f64 = @bitCast(entry.lse_bits);
        const actual_lse = try stable.logSumExp(input[0..entry.len]);
        try std.testing.expect(accuracy.compare(actual_lse, expected_lse).withinUlps(max_ulps));
        var out: [4]f64 = undefined;
        try stable.softmax(input[0..entry.len], out[0..entry.len]);
        for (out[0..entry.len], 0..) |actual, i| {
            const expected: f64 = @bitCast(entry.probabilities[i]);
            try std.testing.expect(accuracy.compare(actual, expected).withinUlps(max_ulps));
        }
    }
}

test "properties: sigmoid symmetry, softplus derivative identity and monotonicity" {
    const xs = [_]f64{ -40, -10, -1, -0.25, 0, 0.25, 1, 10, 40 };
    var previous: f64 = -1;
    for (xs) |x| {
        const s = stable.sigmoid(x);
        const sp = stable.softplus(x);
        try std.testing.expect(s >= previous);
        try std.testing.expect(sp >= 0 and std.math.isFinite(sp));
        try std.testing.expectApproxEqAbs(@as(f64, 1), s + stable.sigmoid(-x), 1e-14);
        // softplus(x) - softplus(-x) = x, avoids numerical differentiation.
        try std.testing.expectApproxEqAbs(x, sp - stable.softplus(-x), 1e-12);
        previous = s;
    }
    try std.testing.expect(std.math.isNan(stable.sigmoid(std.math.nan(f64))));
    try std.testing.expectEqual(@as(f64, 1), stable.sigmoid(std.math.inf(f64)));
    try std.testing.expectEqual(@as(f64, 0), stable.sigmoid(-std.math.inf(f64)));
    try std.testing.expectEqual(std.math.inf(f64), stable.softplus(std.math.inf(f64)));
    try std.testing.expectEqual(@as(f64, 0), stable.softplus(-std.math.inf(f64)));
    const subnormal: f64 = @bitCast(@as(u64, 1));
    try std.testing.expect(std.math.isFinite(stable.softplus(subnormal)));
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), stable.sigmoid(subnormal), 1e-15);
}

test "properties: logSumExp shift and softmax normalization" {
    const values = [_]f64{ -2, -1, 0, 1 };
    const shifted = [_]f64{ 98, 99, 100, 101 };
    const lse = try stable.logSumExp(&values);
    const shifted_lse = try stable.logSumExp(&shifted);
    try std.testing.expectApproxEqAbs(lse + 100, shifted_lse, 1e-12);
    var p: [4]f64 = undefined;
    var q: [4]f64 = undefined;
    try stable.softmax(&values, &p);
    try stable.softmax(&shifted, &q);
    var total: f64 = 0;
    for (p, q) |a, b| {
        total += a;
        try std.testing.expectApproxEqAbs(a, b, 1e-14);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 1), total, 1e-14);
}
