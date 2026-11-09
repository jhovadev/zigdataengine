//! Streaming numerical operations independent of file formats and runtimes.
pub const Moments = @import("moments.zig").Moments;
pub const CompensatedSum = @import("sum.zig").CompensatedSum;
pub const Covariance = @import("covariance.zig").Covariance;
pub const sumFixedTree = @import("deterministic.zig").sumFixedTree;

test {
    _ = @import("moments.zig");
    _ = @import("sum.zig");
    _ = @import("covariance.zig");
    _ = @import("deterministic.zig");
    _ = @import("stress_test.zig");
}
