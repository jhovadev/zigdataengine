//! Compile-time inventory of std.math features in the Zig version actually used.
//! This intentionally does NOT reimplement anything already provided by std.
const std = @import("std");

pub const Features = struct {
    complex: bool,
    big: bool,
    gamma: bool,
    lgamma: bool,
    erf: bool,
    erfc: bool,
    log1p: bool,
    expm1: bool,
    next_after: bool,
};

pub fn inspect() Features {
    return .{
        .complex = @hasDecl(std.math, "complex"),
        .big = @hasDecl(std.math, "big"),
        .gamma = @hasDecl(std.math, "gamma"),
        .lgamma = @hasDecl(std.math, "lgamma"),
        .erf = @hasDecl(std.math, "erf"),
        .erfc = @hasDecl(std.math, "erfc"),
        .log1p = @hasDecl(std.math, "log1p"),
        .expm1 = @hasDecl(std.math, "expm1"),
        .next_after = @hasDecl(std.math, "nextAfter"),
    };
}

test "audit matches installed Zig std declarations" {
    const features = inspect();
    try std.testing.expectEqual(@hasDecl(std.math, "gamma"), features.gamma);
    try std.testing.expectEqual(@hasDecl(std.math, "complex"), features.complex);
}
