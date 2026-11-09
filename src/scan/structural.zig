//! Stateful structural-byte classification over chunks of up to 64 bytes.
//! This is a scalar *reference* kernel, not a SIMD parser or format validator.
//! It reports selected marks only when outside a quoted region.
//! Delimiters, quotes and escapes are parameters, not CSV-specific types.
const std = @import("std");

pub const EscapeMode = enum { none, doubled_quote, backslash };
pub const Dialect = struct {
    /// Structural bytes to report (e.g. "\n", ",\n", or "{}[]:,").
    marks: []const u8,
    /// A quote byte, if quoted regions are supported. Quote marks are excluded
    /// from the returned mask even when included in `marks`.
    quote: ?u8 = null,
    escape: EscapeMode = .none,
};

pub fn Scanner(comptime dialect: Dialect) type {
    comptime {
        if (dialect.escape != .none and dialect.quote == null)
            @compileError("An escape mode requires a quote byte");
    }
    return struct {
        const Self = @This();
        quoted: bool = false,
        /// For doubled quote mode a quote at the end of a chunk may close the
        /// region OR be escaped by the first byte of the following chunk.
        pending_quote: bool = false,
        escaped: bool = false,
        consumed: usize = 0,
        max_bytes: ?usize = null,

        pub fn init(max_bytes: ?usize) Self {
            return .{ .max_bytes = max_bytes };
        }

        /// Returns mask relative to chunk[0]. One call consumes at most 64 bytes.
        /// Empty chunks are allowed. Over-limit/overflow leaves state intact.
        pub fn feed(self: *Self, chunk: []const u8) error{ ChunkTooLarge, InputLimitExceeded, OffsetOverflow }!u64 {
            if (chunk.len > 64) return error.ChunkTooLarge;
            const next = std.math.add(usize, self.consumed, chunk.len) catch return error.OffsetOverflow;
            if (self.max_bytes) |limit| {
                if (next > limit) return error.InputLimitExceeded;
            }
            var result: u64 = 0;
            for (chunk, 0..) |byte, index| {
                if (dialect.quote) |q| {
                    if (dialect.escape == .doubled_quote and self.pending_quote) {
                        self.pending_quote = false;
                        if (byte == q) continue; // "" is one literal quote.
                        self.quoted = false; // previous quote was closing.
                    }
                    if (self.quoted) {
                        if (dialect.escape == .backslash) {
                            if (self.escaped) {
                                self.escaped = false;
                                continue;
                            }
                            if (byte == '\\') {
                                self.escaped = true;
                                continue;
                            }
                        }
                        if (byte == q) {
                            if (dialect.escape == .doubled_quote) {
                                self.pending_quote = true;
                            } else {
                                self.quoted = false;
                            }
                        }
                        continue;
                    }
                    if (byte == q) {
                        self.quoted = true;
                        continue;
                    }
                }
                if (std.mem.indexOfScalar(u8, dialect.marks, byte) != null)
                    result |= @as(u64, 1) << @intCast(index);
            }
            self.consumed = next;
            return result;
        }

        /// Checks only quote/escape termination, not the document grammar.
        pub fn finish(self: *Self) error{UnterminatedQuotedRegion}!void {
            if (self.pending_quote and dialect.escape == .doubled_quote) {
                self.pending_quote = false;
                self.quoted = false;
            }
            if (self.quoted or self.escaped) return error.UnterminatedQuotedRegion;
        }
    };
}

// Independent oracle for testing: classify a one-byte-at-a-time stream.
fn classifySplit(comptime dialect: Dialect, input: []const u8, chunk_len: usize, allocator: std.mem.Allocator) ![]usize {
    var scanner = Scanner(dialect).init(null);
    var output: std.ArrayList(usize) = .empty;
    errdefer output.deinit(allocator);
    var cursor: usize = 0;
    while (cursor < input.len) {
        const end = @min(cursor + chunk_len, input.len);
        const mask = try scanner.feed(input[cursor..end]);
        var buffer: [64]usize = undefined;
        const converted = try @import("../bits/mask64.zig").positions(mask, cursor, &buffer);
        try output.appendSlice(allocator, converted);
        cursor = end;
    }
    try scanner.finish();
    return output.toOwnedSlice(allocator);
}

test "TSV, pipe and newline-only classification share one scanner" {
    const a = std.testing.allocator;
    const cases = .{
        .{ Dialect{ .marks = "\t\n" }, "a\tb\nc\td", &[_]usize{ 1, 3, 5 } },
        .{ Dialect{ .marks = "|\n" }, "a|b\nc|d", &[_]usize{ 1, 3, 5 } },
        .{ Dialect{ .marks = "\n" }, "{\"x\":1}\n{\"x\":2}\n", &[_]usize{ 7, 15 } },
    };
    inline for (cases) |case| {
        const positions = try classifySplit(case[0], case[1], 3, a);
        defer a.free(positions);
        try std.testing.expectEqualSlices(usize, case[2], positions);
    }
}

test "doubled quotes across boundaries do not expose separators" {
    const a = std.testing.allocator;
    const dialect = Dialect{ .marks = ",\n", .quote = '"', .escape = .doubled_quote };
    const input = "a,\"b,\"\"c\"\"\",d\n";
    const expected = try classifySplit(dialect, input, input.len, a);
    defer a.free(expected);
    try std.testing.expectEqualSlices(usize, &.{ 1, 11, 13 }, expected);
    for (1..input.len + 1) |part| {
        const got = try classifySplit(dialect, input, part, a);
        defer a.free(got);
        try std.testing.expectEqualSlices(usize, expected, got);
    }
}

test "JSON style backslash escapes and braces are classified outside strings" {
    const a = std.testing.allocator;
    const dialect = Dialect{ .marks = "{}[]:,", .quote = '"', .escape = .backslash };
    const input = "{\"k\":\"a\\\"b,c\",\"n\":3}";
    const expected = try classifySplit(dialect, input, input.len, a);
    defer a.free(expected);
    for (1..input.len + 1) |size| {
        const got = try classifySplit(dialect, input, size, a);
        defer a.free(got);
        try std.testing.expectEqualSlices(usize, expected, got);
    }
    try std.testing.expectEqual(@as(usize, 5), expected.len);
}

test "scanner enforces limits and reports unterminated regions" {
    const dialect = Dialect{ .marks = ",", .quote = '"', .escape = .doubled_quote };
    var parser = Scanner(dialect).init(3);
    try std.testing.expectEqual(@as(u64, 0), try parser.feed("\"ab"));
    try std.testing.expectError(error.InputLimitExceeded, parser.feed("c"));
    try std.testing.expectEqual(@as(usize, 3), parser.consumed);
    try std.testing.expectError(error.UnterminatedQuotedRegion, parser.finish());
    var long = Scanner(Dialect{ .marks = "," }).init(null);
    try std.testing.expectError(error.ChunkTooLarge, long.feed("........................................................................."));
}

test "structural scan exhaustive fragmentation, including empty chunks" {
    const allocator = std.testing.allocator;
    const dialect = Dialect{ .marks = ",\n", .quote = '"', .escape = .doubled_quote };
    const input = "a,\"b,\"\"c\"\"\",d\n";
    const reference = [_]usize{ 1, 11, 13 };
    // 13 byte boundaries -> 8192 different partitions.
    for (0..(@as(usize, 1) << (input.len - 1))) |split_mask| {
        var scanner = Scanner(dialect).init(null);
        var found: std.ArrayList(usize) = .empty;
        defer found.deinit(allocator);
        var cursor: usize = 0;
        for (1..input.len) |end| {
            if ((split_mask & (@as(usize, 1) << @intCast(end - 1))) == 0) continue;
            const mask = try scanner.feed(input[cursor..end]);
            var scratch: [64]usize = undefined;
            try found.appendSlice(allocator, try @import("../bits/mask64.zig").positions(mask, cursor, &scratch));
            try std.testing.expectEqual(@as(u64, 0), try scanner.feed(""));
            cursor = end;
        }
        const mask = try scanner.feed(input[cursor..]);
        var scratch: [64]usize = undefined;
        try found.appendSlice(allocator, try @import("../bits/mask64.zig").positions(mask, cursor, &scratch));
        try scanner.finish();
        try std.testing.expectEqualSlices(usize, &reference, found.items);
    }
}
