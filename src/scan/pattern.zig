//! KMP: deterministic O(n + m) streaming substring search over arbitrary chunks.
//! Handles patterns split between chunks and overlapping matches.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Matcher = struct {
    allocator: Allocator,
    needle: []u8,
    prefix: []usize,
    matched: usize = 0,
    consumed: usize = 0,

    pub fn init(allocator: Allocator, needle: []const u8) !Matcher {
        if (needle.len == 0) return error.EmptyPattern;
        const owned = try allocator.dupe(u8, needle);
        errdefer allocator.free(owned);
        const prefix = try allocator.alloc(usize, needle.len);
        @memset(prefix, 0);
        var k: usize = 0;
        for (1..needle.len) |i| {
            while (k > 0 and owned[k] != owned[i]) k = prefix[k - 1];
            if (owned[k] == owned[i]) k += 1;
            prefix[i] = k;
        }
        return .{ .allocator = allocator, .needle = owned, .prefix = prefix };
    }

    pub fn deinit(self: *Matcher) void {
        self.allocator.free(self.prefix);
        self.allocator.free(self.needle);
        self.* = undefined;
    }

    pub fn reset(self: *Matcher) void {
        self.matched = 0;
        self.consumed = 0;
    }

    /// Count matches without collecting offsets or allocating memory.
    /// Equivalent to feed() for matched/consumed state, including overlaps.
    pub fn feedCount(self: *Matcher, chunk: []const u8) !usize {
        const next_consumed = try std.math.add(usize, self.consumed, chunk.len);
        var k = self.matched;
        var hits: usize = 0;
        for (chunk) |byte| {
            while (k > 0 and byte != self.needle[k]) k = self.prefix[k - 1];
            if (byte == self.needle[k]) k += 1;
            if (k == self.needle.len) {
                hits += 1;
                k = self.prefix[k - 1];
            }
        }
        self.matched = k;
        self.consumed = next_consumed;
        return hits;
    }

    /// Appends absolute byte offsets to an output list owned by the caller.
    /// On OOM, the partial matcher state is not guaranteed to be resumable.
    pub fn feed(self: *Matcher, chunk: []const u8, out: *std.ArrayList(usize), allocator: Allocator) !void {
        const next_consumed = try std.math.add(usize, self.consumed, chunk.len);
        var k = self.matched;
        for (chunk, 0..) |byte, i| {
            while (k > 0 and byte != self.needle[k]) k = self.prefix[k - 1];
            if (byte == self.needle[k]) k += 1;
            if (k == self.needle.len) {
                const absolute = self.consumed + i + 1 - self.needle.len;
                try out.append(allocator, absolute);
                k = self.prefix[k - 1];
            }
        }
        self.matched = k;
        self.consumed = next_consumed;
    }
};

test "KMP matches overlap across multiple input chunks" {
    const a = std.testing.allocator;
    var matcher = try Matcher.init(a, "aba");
    defer matcher.deinit();
    var matches: std.ArrayList(usize) = .empty;
    defer matches.deinit(a);
    try matcher.feed("a", &matches, a);
    try matcher.feed("ba", &matches, a);
    try matcher.feed("ba", &matches, a);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, matches.items);
    matches.clearRetainingCapacity();
    matcher.reset();
    try matcher.feed("xxxx", &matches, a);
    try std.testing.expectEqual(@as(usize, 0), matches.items.len);
}

test "KMP repeated prefixes, chunk boundary and owned needle" {
    const a = std.testing.allocator;
    var input_pattern = [_]u8{ 'a', 'a', 'a', 'b' };
    var matcher = try Matcher.init(a, &input_pattern);
    defer matcher.deinit();
    input_pattern[0] = 'z'; // Matcher owns a copy.
    var hits: std.ArrayList(usize) = .empty;
    defer hits.deinit(a);
    try matcher.feed("aaaa", &hits, a);
    try matcher.feed("baaab", &hits, a);
    try std.testing.expectEqualSlices(usize, &.{ 1, 5 }, hits.items);
    try std.testing.expectError(error.EmptyPattern, Matcher.init(a, ""));
}

test "feedCount matches collected offsets for overlapping chunk splits" {
    const allocator = std.testing.allocator;
    const data = "ababababa";
    for (1..data.len + 1) |chunk_size| {
        var counting = try Matcher.init(allocator, "aba");
        defer counting.deinit();
        var collecting = try Matcher.init(allocator, "aba");
        defer collecting.deinit();
        var hits: std.ArrayList(usize) = .empty;
        defer hits.deinit(allocator);
        var cursor: usize = 0;
        var count: usize = 0;
        while (cursor < data.len) {
            const end = @min(data.len, cursor + chunk_size);
            count += try counting.feedCount(data[cursor..end]);
            try collecting.feed(data[cursor..end], &hits, allocator);
            cursor = end;
        }
        try std.testing.expectEqual(hits.items.len, count);
        try std.testing.expectEqual(@as(usize, 4), count);
        try std.testing.expectEqual(collecting.matched, counting.matched);
        try std.testing.expectEqual(collecting.consumed, counting.consumed);
        counting.reset();
        try std.testing.expectEqual(@as(usize, 0), try counting.feedCount("zzz"));
    }
}

// Every possible subdivision of the nine-byte input: 2^(9-1) = 256.
// This checks both the collecting API and the allocation-free counting API
// against an independent overlapping-reference implementation.
test "KMP exhaustive fragmentation matches monolithic reference" {
    const a = std.testing.allocator;
    const input = "aaabababa";
    const patterns = [_][]const u8{ "a", "aba", "aaab", "bab", "nomatch" };
    for (patterns) |needle| {
        var expected: std.ArrayList(usize) = .empty;
        defer expected.deinit(a);
        var from: usize = 0;
        while (from < input.len) {
            const relative = std.mem.indexOf(u8, input[from..], needle) orelse break;
            const pos = from + relative;
            try expected.append(a, pos);
            from = pos + 1; // overlaps matter
        }
        for (0..256) |split_mask| {
            var collecting = try Matcher.init(a, needle);
            defer collecting.deinit();
            var counting = try Matcher.init(a, needle);
            defer counting.deinit();
            var actual: std.ArrayList(usize) = .empty;
            defer actual.deinit(a);
            var start: usize = 0;
            var count: usize = 0;
            for (1..input.len) |end| {
                if (split_mask & (@as(usize, 1) << @intCast(end - 1)) == 0) continue;
                try collecting.feed(input[start..end], &actual, a);
                count += try counting.feedCount(input[start..end]);
                // Zero-length chunks must not change state or results.
                try collecting.feed("", &actual, a);
                count += try counting.feedCount("");
                start = end;
            }
            try collecting.feed(input[start..], &actual, a);
            count += try counting.feedCount(input[start..]);
            try std.testing.expectEqualSlices(usize, expected.items, actual.items);
            try std.testing.expectEqual(expected.items.len, count);
            try std.testing.expectEqual(collecting.consumed, counting.consumed);
            try std.testing.expectEqual(collecting.matched, counting.matched);
        }
    }
}

test "KMP randomized chunk boundaries keep offsets stable" {
    const a = std.testing.allocator;
    var input: [4096]u8 = undefined;
    var seed: u64 = 0xdecafbad12345678;
    for (&input) |*b| {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        b.* = if (seed % 5 == 0) 'b' else 'a';
    }
    var reference = try Matcher.init(a, "aaba");
    defer reference.deinit();
    var expected: std.ArrayList(usize) = .empty;
    defer expected.deinit(a);
    try reference.feed(&input, &expected, a);
    for (0..50) |_| {
        var actual: std.ArrayList(usize) = .empty;
        defer actual.deinit(a);
        var fragmented = try Matcher.init(a, "aaba");
        defer fragmented.deinit();
        var cursor: usize = 0;
        while (cursor < input.len) {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            const len: usize = @intCast(seed % 127 + 1);
            const end = @min(input.len, cursor + len);
            try fragmented.feed(input[cursor..end], &actual, a);
            cursor = end;
        }
        try std.testing.expectEqualSlices(usize, expected.items, actual.items);
    }
}

fn checkMatcherAllocationFailures(a: Allocator) !void {
    var matcher = try Matcher.init(a, "abababac");
    defer matcher.deinit();
    try std.testing.expectEqual(@as(usize, 1), try matcher.feedCount("abababac"));
}

test "KMP init cleans up allocations under injected OutOfMemory" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator, checkMatcherAllocationFailures, .{},
    );
}
