//! Small bitmask primitives independent of encodings, parsers and I/O.
pub const mask64 = @import("mask64.zig");
pub const inclusivePrefixXor = mask64.inclusivePrefixXor;
pub const positions = mask64.positions;

test { _ = mask64; }
