//! Bounded-memory portable copying between std.Io streams.
//! Uses caller-owned scratch storage; no implicit file-size allocations.
const std = @import("std");
const io_compat = @import("../compat/io.zig");

pub const Options = struct {
    /// Max bytes to copy; when reached, the source remains positioned there.
    max_bytes: ?u64 = null,
    /// File writers must be flushed before returning successfully.
    flush_on_finish: bool = true,
};

pub const Stats = struct {
    bytes_copied: u64 = 0,
    /// May also be true when EOF lies exactly at max_bytes: EOF is not probed.
    limit_reached: bool = false,
};

/// Copies in bounded chunks; respects partial reads and writer backpressure.
/// Caller controls scratch allocation, lifetime, and reuse.
/// On a read/write error, some bytes may already have been written.
pub fn copy(
    reader: *io_compat.Reader,
    writer: *io_compat.Writer,
    scratch: []u8,
    options: Options,
) (io_compat.ReadError || io_compat.WriteError || error{EmptyBuffer})!Stats {
    if (scratch.len == 0) return error.EmptyBuffer;
    var result: Stats = .{};
    while (true) {
        var allowed = scratch.len;
        if (options.max_bytes) |maximum| {
            if (result.bytes_copied == maximum) {
                result.limit_reached = true;
                break;
            }
            const remaining = maximum - result.bytes_copied;
            allowed = @intCast(@min(remaining, @as(u64, @intCast(scratch.len))));
        }
        const n = try io_compat.readSome(reader, scratch[0..allowed]);
        if (n == 0) break;
        try io_compat.writeAll(writer, scratch[0..n]);
        result.bytes_copied += @intCast(n);
    }
    if (options.flush_on_finish) try io_compat.flush(writer);
    return result;
}

test "copy all bytes in tiny chunks" {
    var source: std.Io.Reader = .fixed("abcdefghij");
    var destination_buf: [16]u8 = undefined;
    var dest: std.Io.Writer = .fixed(&destination_buf);
    var scratch: [3]u8 = undefined;
    const stats = try copy(&source, &dest, &scratch, .{});
    try std.testing.expectEqual(@as(u64, 10), stats.bytes_copied);
    try std.testing.expect(!stats.limit_reached);
    try std.testing.expectEqualStrings("abcdefghij", dest.buffered());
}

test "bounded transfer leaves unread source and never writes past limit" {
    var source: std.Io.Reader = .fixed("abcdefghij");
    var destination_buf: [16]u8 = undefined;
    var dest: std.Io.Writer = .fixed(&destination_buf);
    var scratch: [4]u8 = undefined;
    const stats = try copy(&source, &dest, &scratch, .{ .max_bytes = 5 });
    try std.testing.expectEqual(@as(u64, 5), stats.bytes_copied);
    try std.testing.expect(stats.limit_reached);
    try std.testing.expectEqualStrings("abcde", dest.buffered());
    try std.testing.expectEqual(@as(u8, 'f'), try source.takeByte());
}

test "empty input, empty scratch, and failed writer" {
    var source: std.Io.Reader = .fixed("");
    var destination_buf: [1]u8 = undefined;
    var dest: std.Io.Writer = .fixed(&destination_buf);
    var scratch: [2]u8 = undefined;
    const stats = try copy(&source, &dest, &scratch, .{});
    try std.testing.expectEqual(@as(u64, 0), stats.bytes_copied);
    try std.testing.expectError(error.EmptyBuffer, copy(&source, &dest, scratch[0..0], .{}));
    var second: std.Io.Reader = .fixed("larger than buffer");
    try std.testing.expectError(error.WriteFailed, copy(&second, &dest, &scratch, .{}));
}

test "transfer matches original across scratch sizes and partial limits" {
    const source_bytes = "0123456789abcdef_0123456789abcdef_0123456789abcdef";
    var scratch: [64]u8 = undefined;
    for ([_]usize{ 1, 2, 3, 7, 16, 64 }) |buffer_size| {
        for ([_]u64{ 0, 1, 11, source_bytes.len, source_bytes.len + 5 }) |limit| {
            var reader: std.Io.Reader = .fixed(source_bytes);
            var output: [128]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&output);
            const result = try copy(&reader, &writer, scratch[0..buffer_size], .{ .max_bytes = limit });
            const written: usize = @intCast(@min(limit, source_bytes.len));
            try std.testing.expectEqual(@as(u64, @intCast(written)), result.bytes_copied);
            try std.testing.expectEqualStrings(source_bytes[0..written], writer.buffered());
        }
    }
}
