//! Zig Data Engine (ZData): format-agnostic data primitives.
//! No dependency on UI frameworks, libc, or external packages.
pub const memory = @import("memory/root.zig");
pub const scan = @import("scan/root.zig");
pub const bits = @import("bits/root.zig");
/// Backwards-compatible numeric operations, also available as `stats`.
pub const stats = @import("compute/root.zig");
pub const compute = @import("compute/root.zig");
pub const math = @import("math/root.zig");
pub const transfer = @import("transfer/copy.zig");
pub const compat = @import("compat/io.zig");

test {
    _ = memory;
    _ = scan;
    _ = bits;
    _ = stats;
    _ = compute;
    _ = math;
    _ = transfer;
    _ = compat;
}
