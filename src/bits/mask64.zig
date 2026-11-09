//! Bit zero maps to byte zero. All operations are independent of formats.
const std = @import("std");

/// Inclusive parity prefix for 64 event bits. A set bit at i means an odd
/// number of event bits occurred in [0, i]. This is NOT a quote parser:
/// callers must first classify escaped/doubled quotes correctly.
pub fn inclusivePrefixXor(events: u64) u64 {
    var x = events;
    x ^= x << 1;
    x ^= x << 2;
    x ^= x << 4;
    x ^= x << 8;
    x ^= x << 16;
    x ^= x << 32;
    return x;
}

/// Materializes absolute positions into caller-owned storage. No allocations.
/// Fails before writing when capacity is insufficient or offsets overflow.
pub fn positions(mask: u64, base: usize, out: []usize) error{ OutputTooSmall, OffsetOverflow }![]usize {
    const count: usize = @intCast(@popCount(mask));
    if (out.len < count) return error.OutputTooSmall;
    if (mask != 0) {
        const last: usize = @intCast(63 - @clz(mask));
        _ = std.math.add(usize, base, last) catch return error.OffsetOverflow;
    }
    var pending = mask;
    var i: usize = 0;
    while (pending != 0) {
        const bit: usize = @intCast(@ctz(pending));
        out[i] = base + bit;
        i += 1;
        pending &= pending - 1;
    }
    return out[0..count];
}

test "prefix XOR parity matches scalar reference on all low 12-bit masks" {
    for (0..4096) |value| {
        const input: u64 = @intCast(value);
        var parity: u64 = 0;
        var expected: u64 = 0;
        for (0..64) |bit| {
            parity ^= (input >> @intCast(bit)) & 1;
            expected |= parity << @intCast(bit);
        }
        try std.testing.expectEqual(expected, inclusivePrefixXor(input));
    }
}

test "positions materializes sorted offsets and respects capacity" {
    var buffer: [4]usize = undefined;
    const got = try positions((@as(u64, 1) << 0) | (@as(u64, 1) << 16) | (@as(u64, 1) << 63), 100, &buffer);
    try std.testing.expectEqualSlices(usize, &.{ 100, 116, 163 }, got);
    try std.testing.expectError(error.OutputTooSmall, positions(0b111, 0, buffer[0..2]));
    try std.testing.expectError(error.OffsetOverflow, positions(@as(u64, 1) << 63, std.math.maxInt(usize), &buffer));
    try std.testing.expectEqual(@as(usize, 0), (try positions(0, std.math.maxInt(usize), &buffer)).len);
}
