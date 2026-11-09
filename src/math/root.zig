//! Format-agnostic numerical primitives extending, not duplicating, std.math.
//! No hidden allocation, I/O, global state, or SIMD dispatch.
pub const stable = @import("stable.zig");
pub const precision = @import("precision.zig");
pub const audit = @import("std_audit.zig");
pub const accuracy = @import("accuracy.zig");
// Committed mpmath stress corpus; diagnostic only, not stable API.
pub const stress_golden = @import("stress_golden.zig");

// Diagnostic fixtures: owned by the zdata module, reused by the report executable.
// Not part of the stable numerical API.
pub const golden = @import("golden.zig");

pub const sigmoid = stable.sigmoid;
pub const softplus = stable.softplus;
pub const logSumExp = stable.logSumExp;
pub const softmax = stable.softmax;
pub const ulpDistance = precision.ulpDistance;
pub const almostEqual = precision.almostEqual;

test {
    _ = stable;
    _ = precision;
    _ = audit;
    _ = accuracy;
    _ = @import("golden_test.zig");
    _ = @import("reference_test.zig");
    _ = @import("stress_test.zig");
}
