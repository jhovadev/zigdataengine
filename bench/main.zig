//! M1.7 comparative microbenchmarks. Timings exclude setup and correctness checks.
//! Run: zig build bench -Doptimize=ReleaseFast -- --iterations 30 --warmup 5
const std = @import("std");
const builtin = @import("builtin");
const zdata = @import("zdata");
const stats = @import("stats.zig");

const Options = struct {
    iterations: usize = 30,
    warmup: usize = 5,
    size_mib: usize = 32,
    csv: bool = false,
    samples: bool = false,
};

const Case = enum {
    std_byte,
    zdata_byte,
    vector16,
    vector32,
    std_pattern,
    kmp_stream,
    std_transfer,
    zdata_transfer,
    structural_newline,
};

const Context = struct {
    input: []u8,
    output: []u8,
    scratch: []u8,
    scratch_size: usize = 64 * 1024,
    matcher: *zdata.scan.Matcher,
};

fn parseOptions(args: []const []const u8) !Options {
    var opts: Options = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--csv")) {
            opts.csv = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--samples")) {
            opts.samples = true;
            continue;
        }
        if (i + 1 >= args.len) return error.InvalidArguments;
        i += 1;
        const number = try std.fmt.parseInt(usize, args[i], 10);
        if (std.mem.eql(u8, arg, "--iterations")) {
            opts.iterations = number;
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            opts.warmup = number;
        } else if (std.mem.eql(u8, arg, "--size-mib")) {
            opts.size_mib = number;
        } else {
            return error.InvalidArguments;
        }
    }
    if (opts.csv and opts.samples) return error.InvalidArguments;
    if (opts.iterations == 0 or opts.iterations > 200 or
        opts.warmup > 50 or opts.size_mib == 0 or opts.size_mib > 256)
    {
        return error.OutOfRange;
    }
    return opts;
}

fn countStdPattern(haystack: []const u8, needle: []const u8) usize {
    std.debug.assert(needle.len != 0);
    var hits: usize = 0;
    var cursor: usize = 0;
    while (cursor < haystack.len) {
        const pos = std.mem.indexOf(u8, haystack[cursor..], needle) orelse break;
        hits += 1;
        // Step by one so overlapping matches are counted, just like KMP.
        cursor += pos + 1;
    }
    return hits;
}

fn runCase(which: Case, ctx: *Context) !usize {
    switch (which) {
        .std_byte => return std.mem.count(u8, ctx.input, "\n"),
        .structural_newline => {
            // Generic structural reference kernel: this is intentionally scalar.
            // It must classify the same newlines as std.mem.count on this input.
            const Scanner = zdata.scan.structural.Scanner(.{ .marks = "\n" });
            var scanner = Scanner.init(null);
            var hits: usize = 0;
            var offset: usize = 0;
            while (offset < ctx.input.len) {
                const end = @min(offset + 64, ctx.input.len);
                hits += @popCount(try scanner.feed(ctx.input[offset..end]));
                offset = end;
            }
            try scanner.finish();
            return hits;
        },
        .zdata_byte => return zdata.scan.countByte(ctx.input, '\n'),
        .vector16 => return zdata.scan.countByteVector(16, ctx.input, '\n'),
        .vector32 => return zdata.scan.countByteVector(32, ctx.input, '\n'),
        .std_pattern => return countStdPattern(ctx.input, "AABAA"),
        .kmp_stream => {
            ctx.matcher.reset();
            var chunks = try zdata.scan.Chunks.init(ctx.input, 256 * 1024);
            var total: usize = 0;
            while (chunks.next()) |chunk| total += try ctx.matcher.feedCount(chunk);
            return total;
        },
        .std_transfer => {
            var reader: std.Io.Reader = .fixed(ctx.input);
            var writer: std.Io.Writer = .fixed(ctx.output);
            var total: usize = 0;
            while (true) {
                const n = try reader.readSliceShort(ctx.scratch[0..ctx.scratch_size]);
                if (n == 0) break;
                try writer.writeAll(ctx.scratch[0..n]);
                total += n;
            }
            try writer.flush();
            return total;
        },
        .zdata_transfer => {
            var reader: std.Io.Reader = .fixed(ctx.input);
            var writer: std.Io.Writer = .fixed(ctx.output);
            const result = try zdata.transfer.copy(
                &reader,
                &writer,
                ctx.scratch[0..ctx.scratch_size],
                .{},
            );
            return @intCast(result.bytes_copied);
        },
    }
}

fn isTransfer(which: Case) bool {
    return which == .std_transfer or which == .zdata_transfer;
}

fn runBenchmark(
    io: std.Io,
    allocator: std.mem.Allocator,
    opts: Options,
    label: []const u8,
    which: Case,
    ctx: *Context,
    expected: usize,
) !void {
    const samples = try allocator.alloc(u64, opts.iterations);
    defer allocator.free(samples);
    var checksum: u64 = 0;

    for (0..opts.warmup + opts.iterations) |iteration| {
        const start = std.Io.Clock.awake.now(io);
        const actual = try runCase(which, ctx);
        const elapsed = start.untilNow(io, .awake).toNanoseconds();
        if (elapsed < 0) return error.ClockMovedBackwards;
        // Validate outside the timed interval, including full copied contents.
        if (actual != expected) return error.WrongResult;
        if (isTransfer(which) and !std.mem.eql(u8, ctx.input, ctx.output))
            return error.CorruptTransfer;
        checksum += @intCast(actual);
        if (iteration >= opts.warmup) samples[iteration - opts.warmup] = @intCast(elapsed);
    }

    // summarize sorts its argument: retain original iteration order in --samples.
    const sorted = try allocator.dupe(u64, samples);
    defer allocator.free(sorted);
    const result = try stats.summarize(sorted);
    const mib_s = stats.mibPerSecond(ctx.input.len, result.median_ns);
    if (opts.samples) {
        // Emit every observation, not just a summary. A bootstrap test cannot
        // reconstruct a sampling distribution from median and p95 alone.
        for (samples, 0..) |duration_ns, sample_index| {
            std.debug.print("{s},{d},{d},{d},{d}\n", .{
                label, ctx.input.len, sample_index, duration_ns, expected,
            });
        }
    } else if (opts.csv) {
        std.debug.print("{s},{d},{d},{d},{d},{d},{d},{d},{d:.2},{d}\n", .{
            label,
            ctx.input.len,
            opts.iterations,
            opts.warmup,
            result.minimum_ns,
            result.median_ns,
            result.p95_ns,
            result.maximum_ns,
            mib_s,
            checksum,
        });
    } else {
        std.debug.print("{s}: median={d} us, p95={d} us, {d:.2} MiB/s (checksum={d})\n", .{
            label, result.median_ns / 1000, result.p95_ns / 1000, mib_s, checksum,
        });
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const opts = parseOptions(args) catch |err| {
        std.debug.print(
            "Usage: zdata-bench [--iterations 1..200] [--warmup 0..50] [--size-mib 1..256] [--csv | --samples]\n",
            .{},
        );
        return err;
    };
    const size = try std.math.mul(usize, opts.size_mib, 1024 * 1024);
    const input = try allocator.alloc(u8, size);
    const output = try allocator.alloc(u8, size);
    const scratch = try allocator.alloc(u8, 1024 * 1024);
    @memset(input, 'x');
    @memset(output, 0);
    for (0..size / 8192) |i| {
        const offset = i * 8192;
        input[offset] = '\n';
        @memcpy(input[offset + 100 .. offset + 105], "AABAA");
    }
    const expected_hits = size / 8192;
    var matcher = try zdata.scan.Matcher.init(allocator, "AABAA");
    defer matcher.deinit();
    var ctx: Context = .{ .input = input, .output = output, .scratch = scratch, .matcher = &matcher };

    if (opts.samples) {
        std.debug.print("case,bytes,iteration,ns,checksum\n", .{});
    } else if (opts.csv) {
        std.debug.print("case,bytes,iterations,warmup,min_ns,median_ns,p95_ns,max_ns,mib_per_s,checksum\n", .{});
    } else {
        std.debug.print("zig-data-engine M1.7 comparative benchmark\nTarget: {s}/{s}; mode: {s}\nDataset: {d} MiB; warmup: {d}; iterations: {d}; known buffers: {d} MiB + 1 MiB scratch\n", .{
            @tagName(builtin.target.os.tag),
            @tagName(builtin.target.cpu.arch),
            @tagName(builtin.mode),
            opts.size_mib,
            opts.warmup,
            opts.iterations,
            opts.size_mib * 2,
        });
    }

    try runBenchmark(io, allocator, opts, "std.mem.count(byte)", .std_byte, &ctx, expected_hits);
    try runBenchmark(io, allocator, opts, "zdata.structural.scalar/newline", .structural_newline, &ctx, expected_hits);
    try runBenchmark(io, allocator, opts, "zdata.countByte", .zdata_byte, &ctx, expected_hits);
    try runBenchmark(io, allocator, opts, "zdata.vector16", .vector16, &ctx, expected_hits);
    try runBenchmark(io, allocator, opts, "zdata.vector32", .vector32, &ctx, expected_hits);
    try runBenchmark(io, allocator, opts, "std.mem.indexOf(pattern)", .std_pattern, &ctx, expected_hits);
    try runBenchmark(io, allocator, opts, "zdata.KMP.streaming", .kmp_stream, &ctx, expected_hits);

    // Same std.Io.Reader / Writer fixed-buffer contracts, same content and
    // scratch sizes. This is intentionally not a disk / sendfile benchmark.
    const scenarios = [_]struct { size: usize, std_label: []const u8, zdata_label: []const u8 }{
        .{ .size = 4 * 1024, .std_label = "std.Io.transfer/4KiB", .zdata_label = "zdata.transfer/4KiB" },
        .{ .size = 64 * 1024, .std_label = "std.Io.transfer/64KiB", .zdata_label = "zdata.transfer/64KiB" },
        .{ .size = 256 * 1024, .std_label = "std.Io.transfer/256KiB", .zdata_label = "zdata.transfer/256KiB" },
        .{ .size = 1024 * 1024, .std_label = "std.Io.transfer/1024KiB", .zdata_label = "zdata.transfer/1024KiB" },
    };
    for (scenarios) |scenario| {
        ctx.scratch_size = scenario.size;
        try runBenchmark(io, allocator, opts, scenario.std_label, .std_transfer, &ctx, size);
        try runBenchmark(io, allocator, opts, scenario.zdata_label, .zdata_transfer, &ctx, size);
    }
}

test "option bounds and defaults" {
    const defaults = try parseOptions(&.{"benchmark"});
    try std.testing.expectEqual(@as(usize, 30), defaults.iterations);
    const explicit = try parseOptions(&.{ "benchmark", "--iterations", "12", "--warmup", "0", "--size-mib", "1", "--csv" });
    try std.testing.expectEqual(@as(usize, 12), explicit.iterations);
    try std.testing.expect(explicit.csv);
    const samples = try parseOptions(&.{ "benchmark", "--samples" });
    try std.testing.expect(samples.samples);
    try std.testing.expectError(error.InvalidArguments, parseOptions(&.{ "benchmark", "--csv", "--samples" }));
    try std.testing.expectError(error.OutOfRange, parseOptions(&.{ "benchmark", "--iterations", "0" }));
    try std.testing.expectError(error.InvalidArguments, parseOptions(&.{ "benchmark", "--wat" }));
}

test "reference pattern scan counts overlaps" {
    try std.testing.expectEqual(@as(usize, 3), countStdPattern("aaaaa", "aaa"));
    try std.testing.expectEqual(@as(usize, 0), countStdPattern("", "aaa"));
}
