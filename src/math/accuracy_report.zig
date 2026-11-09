//! Reproducible f64 ULP report against checked-in 100-dps golden vectors.
const std = @import("std");
const zdata = @import("zdata");
const golden = zdata.math.golden;

const Metrics = struct {
    n: u64 = 0,
    total_ulps: u128 = 0,
    max_ulps: u64 = 0,
    max_absolute: f64 = 0,
    max_relative: f64 = 0,

    fn add(self: *Metrics, actual: f64, expected: f64) void {
        const comparison = zdata.math.accuracy.compare(actual, expected);
        const distance = comparison.ulps.?;
        self.n += 1;
        self.total_ulps += distance;
        self.max_ulps = @max(self.max_ulps, distance);
        self.max_absolute = @max(self.max_absolute, comparison.absolute_error.?);
        if (comparison.relative_error) |relative| self.max_relative = @max(self.max_relative, relative);
    }

    fn report(self: Metrics, name: []const u8) void {
        const average: f64 = @as(f64, @floatFromInt(self.total_ulps)) / @as(f64, @floatFromInt(self.n));
        std.debug.print("{s}: cases={d}, max_ulp={d}, mean_ulp={d:.3}, max_abs={d}, max_rel={d}\n", .{
            name, self.n, self.max_ulps, average, self.max_absolute, self.max_relative,
        });
    }
};

pub fn main() !void {
    var sigmoid: Metrics = .{};
    var softplus: Metrics = .{};
    var lse: Metrics = .{};
    var softmax: Metrics = .{};
    for (golden.unary) |entry| {
        const x: f64 = @bitCast(entry.x_bits);
        const want_s: f64 = @bitCast(entry.sigmoid_bits);
        const want_p: f64 = @bitCast(entry.softplus_bits);
        sigmoid.add(zdata.math.sigmoid(x), want_s);
        softplus.add(zdata.math.softplus(x), want_p);
    }
    for (golden.vectors) |entry| {
        var input: [4]f64 = undefined;
        for (entry.inputs, 0..) |word, i| input[i] = @bitCast(word);
        const want_lse: f64 = @bitCast(entry.lse_bits);
        const actual_lse = try zdata.math.logSumExp(input[0..entry.len]);
        lse.add(actual_lse, want_lse);
        var output: [4]f64 = undefined;
        try zdata.math.softmax(input[0..entry.len], output[0..entry.len]);
        for (output[0..entry.len], 0..) |x, i| {
            const expected: f64 = @bitCast(entry.probabilities[i]);
            softmax.add(x, expected);
        }
    }
    var stress_sigmoid: Metrics = .{};
    var stress_softplus: Metrics = .{};
    var stress_lse: Metrics = .{};
    var stress_softmax: Metrics = .{};
    for (zdata.math.stress_golden.unary) |entry| {
        const x: f64 = @bitCast(entry.x_bits);
        const want_s: f64 = @bitCast(entry.sigmoid_bits);
        const want_p: f64 = @bitCast(entry.softplus_bits);
        stress_sigmoid.add(zdata.math.sigmoid(x), want_s);
        stress_softplus.add(zdata.math.softplus(x), want_p);
    }
    for (zdata.math.stress_golden.vectors) |entry| {
        var input: [3]f64 = undefined;
        for (entry.inputs, 0..) |word, i| input[i] = @bitCast(word);
        const want_lse: f64 = @bitCast(entry.lse_bits);
        stress_lse.add(try zdata.math.logSumExp(&input), want_lse);
        var output: [3]f64 = undefined;
        try zdata.math.softmax(&input, &output);
        for (output, entry.probabilities) |actual, bits| {
            const expected: f64 = @bitCast(bits);
            stress_softmax.add(actual, expected);
        }
    }
    std.debug.print("ZDE M1.9 precision report vs mpmath (100 dps)\n", .{});
    sigmoid.report("sigmoid");
    softplus.report("softplus");
    lse.report("logSumExp");
    softmax.report("softmax");
    stress_sigmoid.report("stress.sigmoid");
    stress_softplus.report("stress.softplus");
    stress_lse.report("stress.logSumExp");
    stress_softmax.report("stress.softmax");
    const previous_max = @max(@max(sigmoid.max_ulps, softplus.max_ulps), @max(lse.max_ulps, softmax.max_ulps));
    // The small softmax probabilities in the extended stress corpus use a
    // relative-error gate alongside a wider ULP guard; see docs/m19.
    const strict_stress_max = @max(@max(stress_sigmoid.max_ulps, stress_softplus.max_ulps), stress_lse.max_ulps);
    if (@max(previous_max, strict_stress_max) > 16 or
        stress_softmax.max_ulps > 512 or stress_softmax.max_relative > 1e-12)
        return error.PrecisionRegression;
}
