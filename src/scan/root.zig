//! Scan primitives work on arbitrary bytes, not on CSV rows or JSON values.
pub const bytes = @import("bytes.zig");
pub const pattern = @import("pattern.zig");
pub const structural = @import("structural.zig");

pub const findByte = bytes.findByte;
pub const countByte = bytes.countByte;
pub const countByteVector = bytes.countByteVector;
pub const Chunks = bytes.Chunks;
pub const Matcher = pattern.Matcher;

test {
    _ = bytes;
    _ = pattern;
    _ = structural;
}
