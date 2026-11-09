const std = @import("std");

/// Delegates to Zig's optimized scalar search rather than competing blindly.
pub fn findByte(haystack: []const u8, target: u8) ?usize {
    return std.mem.indexOfScalar(u8, haystack, target);
}

/// Count every occurrence; no allocations and no stored search index.
pub fn countByte(haystack: []const u8, target: u8) usize {
    var count: usize = 0;
    var offset: usize = 0;
    while (findByte(haystack[offset..], target)) |relative| {
        count += 1;
        offset += relative + 1;
    }
    return count;
}

/// Experimental fixed-width vector byte counter. No CPU feature probe or
/// guarantee of hardware SIMD: Zig's backend may scalarize this on some targets.
/// Use countByte() (std-backed) for the default path until a benchmark proves
/// a reproducible gain on the intended target.
pub fn countByteVector(comptime lanes: usize, haystack: []const u8, target: u8) usize {
    comptime {
        if (lanes != 16 and lanes != 32) @compileError("vector width must be 16 or 32");
    }
    const Vec = @Vector(lanes, u8);
    const expected: Vec = @splat(target);
    const yes: Vec = @splat(1);
    const no: Vec = @splat(0);
    var count: usize = 0;
    var i: usize = 0;
    while (haystack.len - i >= lanes) : (i += lanes) {
        // The fixed-size slice is bounds checked before the load; no over-read.
        // Pointer to a fixed-size array with alignment 1: safe on unaligned
        // slices. Loop bound above guarantees all lanes are in range.
        const block_ptr: *align(1) const [lanes]u8 = @ptrCast(haystack[i..].ptr);
        const block: Vec = @bitCast(block_ptr.*);
        const flags: Vec = @select(u8, block == expected, yes, no);
        count += @as(usize, @intCast(@reduce(.Add, flags)));
    }
    for (haystack[i..]) |byte| {
        if (byte == target) count += 1;
    }
    return count;
}

/// Lazy slices for bounded / incremental processing of in-memory input.
pub const Chunks = struct {
    data: []const u8,
    chunk_size: usize,
    cursor: usize = 0,

    pub fn init(data: []const u8, chunk_size: usize) !Chunks {
        if (chunk_size == 0) return error.InvalidChunkSize;
        return .{ .data = data, .chunk_size = chunk_size };
    }

    pub fn next(self: *Chunks) ?[]const u8 {
        if (self.cursor >= self.data.len) return null;
        const size = @min(self.chunk_size, self.data.len - self.cursor);
        const out = self.data[self.cursor .. self.cursor + size];
        self.cursor += size;
        return out;
    }
};

test "byte scan empty, repeated and missing" {
    try std.testing.expect(findByte("", 'x') == null);
    try std.testing.expect(findByte("aaaa", 'b') == null);
    try std.testing.expectEqual(@as(?usize, 0), findByte("abac", 'a'));
    try std.testing.expectEqual(@as(?usize, 3), findByte("abac", 'c'));
    try std.testing.expectEqual(@as(usize, 3), countByte("a--a-a", 'a'));
    try std.testing.expectEqual(@as(usize, 0), countByte("", 'a'));
}

test "bounded chunk iterator preserves all data" {
    var it = try Chunks.init("abcdefg", 3);
    try std.testing.expectEqualStrings("abc", it.next().?);
    try std.testing.expectEqualStrings("def", it.next().?);
    try std.testing.expectEqualStrings("g", it.next().?);
    try std.testing.expect(it.next() == null);
    try std.testing.expectError(error.InvalidChunkSize, Chunks.init("test", 0));
}

// Differential test: compare against a simple scalar reference across many
// lengths and offsets, including tails of 1..31 bytes.
test "vector byte counts match scalar reference on unaligned slices" {
    var data: [1057]u8 = undefined;
    var seed: u64 = 0x9e3779b97f4a7c15;
    for (&data) |*byte| {
        seed ^= seed >> 12;
        seed ^= seed << 25;
        seed ^= seed >> 27;
        byte.* = @truncate(seed);
    }
    for (0..33) |start| {
        for (0..65) |len| {
            const slice = data[start .. start + len];
            for ([_]u8{ 0, 17, 127, 255 }) |needle_byte| {
                var reference: usize = 0;
                for (slice) |b| {
                    if (b == needle_byte) reference += 1;
                }
                try std.testing.expectEqual(reference, countByte(slice, needle_byte));
                try std.testing.expectEqual(reference, countByteVector(16, slice, needle_byte));
                try std.testing.expectEqual(reference, countByteVector(32, slice, needle_byte));
            }
        }
    }
}

test "fuzz vector byte counts" {
    try std.testing.fuzz({}, fuzzVectorCount, .{});
}

fn fuzzVectorCount(_: void, smith: *std.testing.Smith) !void {
    var data: [512]u8 = undefined;
    smith.bytes(&data);
    // Smith requires an integer with a fixed bit width, not usize.
    const n = @import("../testing/smith.zig").boundedLen(smith, data.len);
    const target: u8 = smith.value(u8);
    const slice = data[0..n];
    var reference: usize = 0;
    for (slice) |byte| {
        if (byte == target) reference += 1;
    }
    try std.testing.expectEqual(reference, countByte(slice, target));
    try std.testing.expectEqual(reference, countByteVector(16, slice, target));
    try std.testing.expectEqual(reference, countByteVector(32, slice, target));
}
