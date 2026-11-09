//! Opt-in measurement wrapper; NEVER a replacement for an allocator.
//! Measures requested bytes, not RSS or underlying arena page retention.
//! Not thread-safe: create one instance per worker or externally synchronize.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Stats = struct {
    live_bytes: usize = 0,
    peak_bytes: usize = 0,
    total_requested_bytes: usize = 0,
    alloc_calls: usize = 0,
    resize_calls: usize = 0,
    remap_calls: usize = 0,
    free_calls: usize = 0,
    failed_calls: usize = 0,
    budget_denials: usize = 0,
};

pub const CountingAllocator = struct {
    backing: Allocator,
    stats: Stats = .{},
    /// Maximum *requested live bytes*. Null means unlimited. Not RSS.
    limit_bytes: ?usize = null,

    pub fn init(backing: Allocator) CountingAllocator {
        return .{ .backing = backing };
    }

    /// Enforces a live-allocation budget without replacing Zig's backing allocator.
    /// Non-thread-safe. When realloc must move, old and new allocations can
    /// temporarily coexist, so it may fail even when the final size fits.
    pub fn initWithBudget(backing: Allocator, max_live_bytes: usize) CountingAllocator {
        return .{ .backing = backing, .limit_bytes = max_live_bytes };
    }

    pub fn remainingBudget(self: *const CountingAllocator) ?usize {
        const limit = self.limit_bytes orelse return null;
        return limit -| self.stats.live_bytes;
    }

    fn canGrow(self: *const CountingAllocator, increase: usize) bool {
        const remaining = self.remainingBudget() orelse return true;
        return increase <= remaining;
    }

    fn recordBudgetDenial(self: *CountingAllocator) void {
        self.stats.failed_calls += 1;
        self.stats.budget_denials += 1;
    }

    /// Returned allocator borrows `self`. Do not move this object while in use.
    /// To disable instrumentation entirely, pass the backing allocator instead.
    pub fn allocator(self: *CountingAllocator) Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn recordGrowth(self: *CountingAllocator, bytes: usize) void {
        self.stats.live_bytes += bytes;
        self.stats.total_requested_bytes += bytes;
        self.stats.peak_bytes = @max(self.stats.peak_bytes, self.stats.live_bytes);
    }

    fn recordShrink(self: *CountingAllocator, bytes: usize) void {
        std.debug.assert(self.stats.live_bytes >= bytes);
        self.stats.live_bytes -= bytes;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.stats.alloc_calls += 1;
        if (!self.canGrow(len)) {
            self.recordBudgetDenial();
            return null;
        }
        const ptr = self.backing.rawAlloc(len, alignment, ret_addr) orelse {
            self.stats.failed_calls += 1;
            return null;
        };
        self.recordGrowth(len);
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.stats.resize_calls += 1;
        if (new_len > memory.len and !self.canGrow(new_len - memory.len)) {
            self.recordBudgetDenial();
            return false;
        }
        if (!self.backing.rawResize(memory, alignment, new_len, ret_addr)) return false;
        if (new_len >= memory.len) self.recordGrowth(new_len - memory.len)
        else self.recordShrink(memory.len - new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.stats.remap_calls += 1;
        if (new_len > memory.len and !self.canGrow(new_len - memory.len)) {
            self.recordBudgetDenial();
            return null;
        }
        const ptr = self.backing.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        if (new_len >= memory.len) self.recordGrowth(new_len - memory.len)
        else self.recordShrink(memory.len - new_len);
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.stats.free_calls += 1;
        self.backing.rawFree(memory, alignment, ret_addr);
        self.recordShrink(memory.len);
    }

    const vtable: Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };
};

test "counting allocator tracks live and peak bytes without leaks" {
    var counter: CountingAllocator = .init(std.testing.allocator);
    const a = counter.allocator();
    const first = try a.alloc(u8, 16);
    const second = try a.alloc(u8, 32);
    try std.testing.expectEqual(@as(usize, 48), counter.stats.peak_bytes);
    try std.testing.expectEqual(@as(usize, 48), counter.stats.live_bytes);
    a.free(first);
    try std.testing.expectEqual(@as(usize, 32), counter.stats.live_bytes);
    a.free(second);
    try std.testing.expectEqual(@as(usize, 0), counter.stats.live_bytes);
    try std.testing.expectEqual(@as(usize, 2), counter.stats.alloc_calls);
}

test "counting allocator records allocation errors" {
    var counter: CountingAllocator = .init(Allocator.failing);
    try std.testing.expectError(error.OutOfMemory, counter.allocator().alloc(u8, 16));
    try std.testing.expectEqual(@as(usize, 1), counter.stats.failed_calls);
    try std.testing.expectEqual(@as(usize, 0), counter.stats.live_bytes);
}

test "counting allocator measures pool init and restores zero live bytes" {
    var counter: CountingAllocator = .init(std.testing.allocator);
    var fixed_pool = try @import("pool.zig").Pool.init(counter.allocator(), 128, 3);
    try std.testing.expect(counter.stats.peak_bytes >= 384);
    var lease = fixed_pool.acquire().?;
    lease.bytes()[0] = 17;
    lease.release();
    fixed_pool.deinit();
    try std.testing.expectEqual(@as(usize, 0), counter.stats.live_bytes);
}

test "counting allocator works with an owned streaming matcher" {
    const Matcher = @import("../scan/pattern.zig").Matcher;
    var counter: CountingAllocator = .init(std.testing.allocator);
    const allocator = counter.allocator();
    var matcher = try Matcher.init(allocator, "abc");
    try std.testing.expect(counter.stats.peak_bytes >= 3);
    try std.testing.expectEqual(@as(usize, 1), try matcher.feedCount("abc"));
    matcher.deinit();
    try std.testing.expectEqual(@as(usize, 0), counter.stats.live_bytes);
}


test "budget refuses excess allocation and preserves live-byte accounting" {
    var meter = CountingAllocator.initWithBudget(std.testing.allocator, 24);
    const a = meter.allocator();
    const first = try a.alloc(u8, 16);
    try std.testing.expectEqual(@as(?usize, 8), meter.remainingBudget());
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 9));
    try std.testing.expectEqual(@as(usize, 1), meter.stats.budget_denials);
    try std.testing.expectEqual(@as(usize, 16), meter.stats.live_bytes);
    const second = try a.alloc(u8, 8);
    try std.testing.expectEqual(@as(usize, 24), meter.stats.peak_bytes);
    try std.testing.expectEqual(@as(?usize, 0), meter.remainingBudget());
    a.free(first);
    a.free(second);
    try std.testing.expectEqual(@as(usize, 0), meter.stats.live_bytes);
    try std.testing.expectEqual(@as(?usize, 24), meter.remainingBudget());
}

test "budget supports shrink and realloc without losing live-byte accounting" {
    var meter = CountingAllocator.initWithBudget(std.testing.allocator, 24);
    const a = meter.allocator();
    var data = try a.alloc(u8, 16);
    data[0] = 91;
    // Realloc down must succeed even at a strict budget.
    data = try a.realloc(data, 8);
    try std.testing.expectEqual(@as(u8, 91), data[0]);
    try std.testing.expectEqual(@as(usize, 8), meter.stats.live_bytes);
    const another = try a.alloc(u8, 16);
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 1));
    a.free(another);
    a.free(data);
    try std.testing.expectEqual(@as(usize, 0), meter.stats.live_bytes);
}

test "zero-budget allocation is rejected but an empty budget is usable later" {
    var meter = CountingAllocator.initWithBudget(std.testing.allocator, 0);
    try std.testing.expectError(error.OutOfMemory, meter.allocator().alloc(u8, 1));
    try std.testing.expectEqual(@as(usize, 1), meter.stats.budget_denials);
    try std.testing.expectEqual(@as(usize, 0), meter.stats.live_bytes);
}
