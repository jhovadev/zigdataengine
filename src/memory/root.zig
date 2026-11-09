// Preserve the M0 public path: zdata.memory.Pool.
pub const Pool = @import("pool.zig").Pool;
pub const pool = @import("pool.zig");
pub const CountingAllocator = @import("counting.zig").CountingAllocator;
pub const AllocatorStats = @import("counting.zig").Stats;

test {
    _ = Pool;
    _ = pool;
    _ = @import("counting.zig");
}
