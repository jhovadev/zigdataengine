//! zig build math-audit: inspect std.math symbols in the compiler in use.
const std = @import("std");
const zde = @import("zdata");

pub fn main() void {
    const f = zde.math.audit.inspect();
    std.debug.print("std.math inventory (installed Zig):\n", .{});
    std.debug.print("  complex={} big={} gamma={} lgamma={}\n", .{ f.complex, f.big, f.gamma, f.lgamma });
    std.debug.print("  erf={} erfc={} log1p={} expm1={} nextAfter={}\n", .{
        f.erf, f.erfc, f.log1p, f.expm1, f.next_after,
    });
    std.debug.print("ZDE math: sigmoid, softplus, logSumExp, softmax, ulpDistance, almostEqual\n", .{});
}
