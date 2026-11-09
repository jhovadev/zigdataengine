//! M1.9 independent numeric microbenchmarks: latency AND f128 accuracy.
//! No setup, reference computation, or checks inside timed regions.
//! --samples reuses the exact M1.5 CSV schema for bench_compare.py.
const std = @import("std");
const builtin = @import("builtin");
const zde = @import("zdata");
const bench_stats = @import("stats.zig");

const Options = struct {
    iterations: usize = 30,
    warmup: usize = 5,
    size: usize = 32768,
    samples: bool = false,
};

const Case = enum {
    naive_sum,
    compensated_sum,
    fixed_tree_sum,
    two_pass_variance,
    moments_online,
    moments_merge8,
    two_pass_covariance,
    covariance_online,
    covariance_merge8,
    scalar_sigmoid,
    zde_sigmoid,
    scalar_softplus,
    zde_softplus,
};

const Context = struct { x: []f64, y: []f64, unary: []f64, sum_values: []f64 };
const Reference = struct {
    sum: f64,
    variance: f64,
    covariance: f64,
    sigmoid_sum: f64,
    softplus_sum: f64,
};

fn parseOptions(args: []const []const u8) !Options {
    var opts: Options = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const flag = args[i];
        if (std.mem.eql(u8, flag, "--samples")) {
            opts.samples = true;
            continue;
        }
        if (i + 1 >= args.len) return error.InvalidArguments;
        i += 1;
        const value = try std.fmt.parseInt(usize, args[i], 10);
        if (std.mem.eql(u8, flag, "--size")) opts.size = value else if (std.mem.eql(u8, flag, "--iterations")) opts.iterations = value else if (std.mem.eql(u8, flag, "--warmup")) opts.warmup = value else return error.InvalidArguments;
    }
    if (opts.size < 8 or opts.size > 1_048_576 or opts.size % 8 != 0 or
        opts.iterations < 1 or opts.iterations > 200 or opts.warmup > 50)
        return error.OutOfRange;
    return opts;
}

fn prepare(allocator: std.mem.Allocator, n: usize) !Context {
    const x = try allocator.alloc(f64, n);
    errdefer allocator.free(x);
    const y = try allocator.alloc(f64, n);
    errdefer allocator.free(y);
    const unary = try allocator.alloc(f64, n);
    errdefer allocator.free(unary);
    const sum_values = try allocator.alloc(f64, n);
    errdefer allocator.free(sum_values);
    for (0..n) |i| {
        const a: i64 = @intCast((i * 73 + 19) % 233);
        const b: i64 = @intCast((i * 149 + 37) % 191);
        x[i] = 1_000_000.0 + @as(f64, @floatFromInt(a - 116)) / 32.0;
        y[i] = -400_000.0 + @as(f64, @floatFromInt(b - 95)) / 64.0;
        const v: i64 = @intCast((i * 251 + 43) % 1009);
        unary[i] = @as(f64, @floatFromInt(v - 504)) / 32.0;
        // Cancellation-heavy workload: naive f64 loses the 1-valued term.
        sum_values[i] = switch (i % 4) {
            0 => 1e16,
            1 => 1,
            2 => -1e16,
            else => 2,
        };
    }
    return .{ .x = x, .y = y, .unary = unary, .sum_values = sum_values };
}

fn references(ctx: Context) Reference {
    const n: f128 = @floatFromInt(ctx.x.len);
    var xs: f128 = 0;
    var ys: f128 = 0;
    var sig: f128 = 0;
    var sp: f128 = 0;
    var sum_values: f128 = 0;
    for (ctx.x, ctx.y, ctx.unary, ctx.sum_values) |x, y, unary, sv| {
        xs += @as(f128, x);
        sum_values += @as(f128, sv);
        ys += @as(f128, y);
        const v: f128 = unary;
        sig += 1.0 / (1.0 + @exp(-v));
        sp += @log(1.0 + @exp(v));
    }
    const mx = xs / n;
    const my = ys / n;
    var var_x: f128 = 0;
    var cov: f128 = 0;
    for (ctx.x, ctx.y) |x, y| {
        const dx = @as(f128, x) - mx;
        var_x += dx * dx;
        cov += dx * (@as(f128, y) - my);
    }
    return .{
        .sum = @floatCast(sum_values),
        .variance = @floatCast(var_x / n),
        .covariance = @floatCast(cov / n),
        .sigmoid_sum = @floatCast(sig),
        .softplus_sum = @floatCast(sp),
    };
}

fn twoPassVariance(ctx: Context) f64 {
    var total: f64 = 0;
    for (ctx.x) |x| total += x;
    const mean = total / @as(f64, @floatFromInt(ctx.x.len));
    var m2: f64 = 0;
    for (ctx.x) |x| {
        const d = x - mean;
        m2 += d * d;
    }
    return m2 / @as(f64, @floatFromInt(ctx.x.len));
}

fn twoPassCovariance(ctx: Context) f64 {
    var total_x: f64 = 0;
    var total_y: f64 = 0;
    for (ctx.x, ctx.y) |x, y| {
        total_x += x;
        total_y += y;
    }
    const n: f64 = @floatFromInt(ctx.x.len);
    const mx = total_x / n;
    const my = total_y / n;
    var c: f64 = 0;
    for (ctx.x, ctx.y) |x, y| c += (x - mx) * (y - my);
    return c / n;
}

fn runCase(which: Case, ctx: Context) !f64 {
    switch (which) {
        .naive_sum => {
            var value: f64 = 0;
            for (ctx.sum_values) |x| value += x;
            return value;
        },
        .compensated_sum => {
            var value: zde.stats.CompensatedSum = .{};
            for (ctx.sum_values) |x| try value.update(x);
            return value.finish();
        },
        .fixed_tree_sum => return zde.stats.sumFixedTree(ctx.sum_values),
        .two_pass_variance => return twoPassVariance(ctx),
        .moments_online => {
            var value: zde.stats.Moments = .{};
            for (ctx.x) |x| try value.update(x);
            return value.populationVariance().?;
        },
        .moments_merge8 => {
            var parts: [8]zde.stats.Moments = undefined;
            for (&parts) |*part| part.* = .{};
            const step = ctx.x.len / 8;
            for (0..8) |p| {
                for (ctx.x[p * step .. (p + 1) * step]) |x| try parts[p].update(x);
            }
            var value: zde.stats.Moments = .{};
            for (parts) |part| try value.merge(part);
            return value.populationVariance().?;
        },
        .two_pass_covariance => return twoPassCovariance(ctx),
        .covariance_online => {
            var value: zde.stats.Covariance = .{};
            for (ctx.x, ctx.y) |x, y| try value.update(x, y);
            return value.populationCovariance().?;
        },
        .covariance_merge8 => {
            var parts: [8]zde.stats.Covariance = undefined;
            for (&parts) |*part| part.* = .{};
            const step = ctx.x.len / 8;
            for (0..8) |p| {
                for (ctx.x[p * step .. (p + 1) * step], ctx.y[p * step .. (p + 1) * step]) |x, y|
                    try parts[p].update(x, y);
            }
            var value: zde.stats.Covariance = .{};
            for (parts) |part| try value.merge(part);
            return value.populationCovariance().?;
        },
        .scalar_sigmoid => {
            var sum: f64 = 0;
            for (ctx.unary) |x| sum += 1.0 / (1.0 + @exp(-x));
            return sum;
        },
        .zde_sigmoid => {
            var sum: f64 = 0;
            for (ctx.unary) |x| sum += zde.math.sigmoid(x);
            return sum;
        },
        .scalar_softplus => {
            var sum: f64 = 0;
            for (ctx.unary) |x| sum += std.math.log1p(@exp(x));
            return sum;
        },
        .zde_softplus => {
            var sum: f64 = 0;
            for (ctx.unary) |x| sum += zde.math.softplus(x);
            return sum;
        },
    }
}

fn referenceFor(which: Case, r: Reference) f64 {
    return switch (which) {
        .naive_sum, .compensated_sum, .fixed_tree_sum => r.sum,
        .two_pass_variance, .moments_online, .moments_merge8 => r.variance,
        .two_pass_covariance, .covariance_online, .covariance_merge8 => r.covariance,
        .scalar_sigmoid, .zde_sigmoid => r.sigmoid_sum,
        .scalar_softplus, .zde_softplus => r.softplus_sum,
    };
}

fn maxAbsoluteError(which: Case) f64 {
    return switch (which) {
        // The baseline intentionally accumulates uncorrected f64 roundoff.
        .naive_sum => 1e100,
        .compensated_sum, .fixed_tree_sum => 0.0001,
        .two_pass_variance, .moments_online, .moments_merge8 => 0.0001,
        .two_pass_covariance, .covariance_online, .covariance_merge8 => 0.0001,
        .scalar_sigmoid, .zde_sigmoid => 0.00001,
        .scalar_softplus, .zde_softplus => 0.001,
    };
}

fn runBenchmark(io: std.Io, allocator: std.mem.Allocator, opts: Options, ctx: Context, r: Reference, which: Case, label: []const u8) !void {
    const expected = referenceFor(which, r);
    const samples = try allocator.alloc(u64, opts.iterations);
    defer allocator.free(samples);
    var final_value: f64 = 0;
    for (0..opts.warmup + opts.iterations) |i| {
        const start = std.Io.Clock.awake.now(io);
        const actual = try runCase(which, ctx);
        const elapsed = start.untilNow(io, .awake).toNanoseconds();
        if (elapsed <= 0) return error.ClockResolutionTooLow;
        // All error checks after timed scope; do not force identical rounding.
        if (!std.math.isFinite(actual) or @abs(actual - expected) > maxAbsoluteError(which))
            return error.NumericRegression;
        final_value = actual;
        if (i >= opts.warmup) samples[i - opts.warmup] = @intCast(elapsed);
    }
    const sorted = try allocator.dupe(u64, samples);
    defer allocator.free(sorted);
    const summary = try bench_stats.summarize(sorted);
    const error_report = zde.math.accuracy.compare(final_value, expected);
    const fingerprint: u64 = @bitCast(expected);
    // ``bytes`` is the total x/y/unary/sum_values allocation, not the exact bytes
    // touched by each kernel. Run only same-case baseline comparisons.
    const footprint = ctx.x.len * 4 * @sizeOf(f64);
    if (opts.samples) {
        for (samples, 0..) |ns, iteration| std.debug.print("{s},{d},{d},{d},{d}\n", .{
            label, footprint, iteration, ns, fingerprint,
        });
    } else {
        std.debug.print("{s}: median={d} us p95={d} us; abs_error={d} ulps={any}\n", .{
            label, summary.median_ns / 1000, summary.p95_ns / 1000,
            error_report.absolute_error.?, error_report.ulps,
        });
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const opts = parseOptions(args) catch |err| {
        std.debug.print("Usage: zig build math-bench -- [--size 8..1048576 multiple-of-8] [--iterations 1..200] [--warmup 0..50] [--samples]\n", .{});
        return err;
    };
    const ctx = try prepare(allocator, opts.size);
    const r = references(ctx);
    if (opts.samples) {
        std.debug.print("case,bytes,iteration,ns,checksum\n", .{});
    } else {
        std.debug.print("ZDE M1.9 numeric benchmark | {s}/{s} | {s} | n={d}, iterations={d}, warmup={d} | reference=f128 two-pass\n", .{
            @tagName(builtin.target.os.tag), @tagName(builtin.target.cpu.arch),
            @tagName(builtin.mode), opts.size, opts.iterations, opts.warmup,
        });
    }
    const cases = [_]struct { case: Case, name: []const u8 }{
        .{ .case = .naive_sum, .name = "baseline.naive.sum" },
        .{ .case = .compensated_sum, .name = "zdata.sum.neumaier" },
        .{ .case = .fixed_tree_sum, .name = "zdata.sum.fixed-tree" },
        .{ .case = .two_pass_variance, .name = "baseline.two-pass.variance" },
        .{ .case = .moments_online, .name = "zdata.moments.online" },
        .{ .case = .moments_merge8, .name = "zdata.moments.merge8" },
        .{ .case = .two_pass_covariance, .name = "baseline.two-pass.covariance" },
        .{ .case = .covariance_online, .name = "zdata.covariance.online" },
        .{ .case = .covariance_merge8, .name = "zdata.covariance.merge8" },
        .{ .case = .scalar_sigmoid, .name = "baseline.scalar.sigmoid" },
        .{ .case = .zde_sigmoid, .name = "zdata.math.sigmoid" },
        .{ .case = .scalar_softplus, .name = "baseline.scalar.softplus" },
        .{ .case = .zde_softplus, .name = "zdata.math.softplus" },
    };
    for (cases) |one| try runBenchmark(init.io, allocator, opts, ctx, r, one.case, one.name);
}

test "argument validation" {
    try std.testing.expectError(error.OutOfRange, parseOptions(&.{ "numeric", "--size", "7" }));
    try std.testing.expectError(error.InvalidArguments, parseOptions(&.{ "numeric", "--bad" }));
    try std.testing.expectEqual(@as(usize, 32768), (try parseOptions(&.{"numeric"})).size);
}

test "numerical benchmark reference and kernels on small dataset" {
    const allocator = std.testing.allocator;
    const ctx = try prepare(allocator, 256);
    defer allocator.free(ctx.x);
    defer allocator.free(ctx.y);
    defer allocator.free(ctx.unary);
    defer allocator.free(ctx.sum_values);
    const r = references(ctx);
    const cases = [_]Case{
        .naive_sum, .compensated_sum, .fixed_tree_sum,
        .two_pass_variance, .moments_online, .moments_merge8,
        .two_pass_covariance, .covariance_online, .covariance_merge8,
        .scalar_sigmoid, .zde_sigmoid, .scalar_softplus, .zde_softplus,
    };
    for (cases) |which| {
        const actual = try runCase(which, ctx);
        try std.testing.expect(std.math.isFinite(actual));
        try std.testing.expect(@abs(actual - referenceFor(which, r)) <= maxAbsoluteError(which));
    }
}
