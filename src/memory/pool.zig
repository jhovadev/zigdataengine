//! Fixed-capacity, reuse-oriented byte buffer pool.
//! Not thread-safe. Each Lease must have only one logical owner.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Pool = struct {
    allocator: Allocator,
    storage: []u8,
    free_indices: []usize,
    occupied: []bool,
    slot_size: usize,
    available: usize,

    /// Exactly three allocations at creation, zero allocations during acquire/release.
    /// `slot_size` and `slot_count` must both be positive.
    pub fn init(allocator: Allocator, slot_size: usize, slot_count: usize) !Pool {
        if (slot_size == 0 or slot_count == 0) return error.InvalidCapacity;
        const byte_count = try std.math.mul(usize, slot_size, slot_count);
        const storage = try allocator.alloc(u8, byte_count);
        errdefer allocator.free(storage);
        const free_indices = try allocator.alloc(usize, slot_count);
        errdefer allocator.free(free_indices);
        const occupied = try allocator.alloc(bool, slot_count);
        errdefer allocator.free(occupied);
        @memset(occupied, false);
        for (0..slot_count) |i| free_indices[i] = slot_count - i - 1;
        return .{
            .allocator = allocator,
            .storage = storage,
            .free_indices = free_indices,
            .occupied = occupied,
            .slot_size = slot_size,
            .available = slot_count,
        };
    }

    pub fn deinit(self: *Pool) void {
        // All leases must be returned before the pool is freed.
        std.debug.assert(self.available == self.occupied.len);
        self.allocator.free(self.occupied);
        self.allocator.free(self.free_indices);
        self.allocator.free(self.storage);
        self.* = undefined;
    }

    /// Null means the pool is fully leased, never an allocation failure.
    pub fn acquire(self: *Pool) ?Lease {
        if (self.available == 0) return null;
        self.available -= 1;
        const index = self.free_indices[self.available];
        std.debug.assert(!self.occupied[index]);
        self.occupied[index] = true;
        return .{ .pool = self, .index = index };
    }

    fn returnIndex(self: *Pool, index: usize) void {
        std.debug.assert(index < self.occupied.len);
        std.debug.assert(self.occupied[index]);
        self.occupied[index] = false;
        self.free_indices[self.available] = index;
        self.available += 1;
    }

    pub const Lease = struct {
        pool: *Pool,
        index: usize,
        active: bool = true,

        /// Borrowed bytes; never retain across release().
        pub fn bytes(self: *Lease) []u8 {
            std.debug.assert(self.active);
            const start = self.index * self.pool.slot_size;
            return self.pool.storage[start .. start + self.pool.slot_size];
        }

        /// The lease must not be copied or released twice.
        pub fn release(self: *Lease) void {
            std.debug.assert(self.active);
            self.pool.returnIndex(self.index);
            self.active = false;
        }
    };
};

test "pool reuses fixed buffers and enforces capacity" {
    var pool = try Pool.init(std.testing.allocator, 16, 2);
    defer pool.deinit();
    var first = pool.acquire().?;
    var second = pool.acquire().?;
    try std.testing.expect(pool.acquire() == null);
    @memset(first.bytes(), 42);
    @memset(second.bytes(), 11);
    try std.testing.expectEqual(@as(u8, 42), first.bytes()[0]);
    try std.testing.expectEqual(@as(u8, 11), second.bytes()[0]);
    first.release();
    var reused = pool.acquire().?;
    try std.testing.expectEqual(@as(usize, 16), reused.bytes().len);
    reused.release();
    second.release();
    try std.testing.expectEqual(@as(usize, 2), pool.available);
}

test "pool rejects impossible sizes" {
    try std.testing.expectError(error.InvalidCapacity, Pool.init(std.testing.allocator, 0, 2));
    try std.testing.expectError(error.InvalidCapacity, Pool.init(std.testing.allocator, 128, 0));
    try std.testing.expectError(error.Overflow, Pool.init(std.testing.allocator, std.math.maxInt(usize), 2));
}
