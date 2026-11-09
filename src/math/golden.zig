//! Generated with tools/generate_math_vectors.py using mpmath (100 dps).
//! Golden f64 outputs are rounded from arbitrary-precision expressions.
//! DO NOT EDIT: run `python3 tools/generate_math_vectors.py --check`.
pub const Unary = struct { x_bits: u64, sigmoid_bits: u64, softplus_bits: u64 };
pub const unary = [_]Unary{
    .{ .x_bits = 0xc08f400000000000, .sigmoid_bits = 0x0000000000000000, .softplus_bits = 0x0000000000000000 },
    .{ .x_bits = 0xc087480000000000, .sigmoid_bits = 0x0000000000000001, .softplus_bits = 0x0000000000000001 },
    .{ .x_bits = 0xc087200000000000, .sigmoid_bits = 0x0000000000000055, .softplus_bits = 0x0000000000000055 },
    .{ .x_bits = 0xc086300000000000, .sigmoid_bits = 0x00033802fd28b3c3, .softplus_bits = 0x00033802fd28b3c3 },
    .{ .x_bits = 0xc059000000000000, .sigmoid_bits = 0x36ea8c1f14e2af5d, .softplus_bits = 0x36ea8c1f14e2af5d },
    .{ .x_bits = 0xc044000000000000, .sigmoid_bits = 0x3c539792499b1a24, .softplus_bits = 0x3c539792499b1a24 },
    .{ .x_bits = 0xc034000000000000, .sigmoid_bits = 0x3e21b4865556b5d5, .softplus_bits = 0x3e21b48655a5141e },
    .{ .x_bits = 0xc014000000000000, .sigmoid_bits = 0x3f7b69f67d638f8e, .softplus_bits = 0x3f7b818da245a728 },
    .{ .x_bits = 0xc000000000000000, .sigmoid_bits = 0x3fbe84152bac31af, .softplus_bits = 0x3fc03f2d54301d49 },
    .{ .x_bits = 0xbff0000000000000, .sigmoid_bits = 0x3fd136561454ba86, .softplus_bits = 0x3fd40c7abfbec124 },
    .{ .x_bits = 0xbd719799812dea11, .sigmoid_bits = 0x3fdfffffffffee68, .softplus_bits = 0x3fe62e42fefa2858 },
    .{ .x_bits = 0x8000000000000000, .sigmoid_bits = 0x3fe0000000000000, .softplus_bits = 0x3fe62e42fefa39ef },
    .{ .x_bits = 0x0000000000000000, .sigmoid_bits = 0x3fe0000000000000, .softplus_bits = 0x3fe62e42fefa39ef },
    .{ .x_bits = 0x3d719799812dea11, .sigmoid_bits = 0x3fe00000000008cc, .softplus_bits = 0x3fe62e42fefa4b87 },
    .{ .x_bits = 0x3ff0000000000000, .sigmoid_bits = 0x3fe764d4f5d5a2bd, .softplus_bits = 0x3ff5031eafefb049 },
    .{ .x_bits = 0x4000000000000000, .sigmoid_bits = 0x3fec2f7d5a8a79ca, .softplus_bits = 0x400103f2d54301d5 },
    .{ .x_bits = 0x4014000000000000, .sigmoid_bits = 0x3fefc92c130538e1, .softplus_bits = 0x401406e06368916a },
    .{ .x_bits = 0x4034000000000000, .sigmoid_bits = 0x3feffffffee4b79b, .softplus_bits = 0x403400000008da43 },
    .{ .x_bits = 0x4044000000000000, .sigmoid_bits = 0x3ff0000000000000, .softplus_bits = 0x4044000000000000 },
    .{ .x_bits = 0x4059000000000000, .sigmoid_bits = 0x3ff0000000000000, .softplus_bits = 0x4059000000000000 },
    .{ .x_bits = 0x4086280000000000, .sigmoid_bits = 0x3ff0000000000000, .softplus_bits = 0x4086280000000000 },
    .{ .x_bits = 0x408f400000000000, .sigmoid_bits = 0x3ff0000000000000, .softplus_bits = 0x408f400000000000 },
};
pub const Vector = struct { len: usize, inputs: [4]u64, lse_bits: u64, probabilities: [4]u64 };
pub const vectors = [_]Vector{
    .{ .len = 2, .inputs = .{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 }, .lse_bits = 0x3fe62e42fefa39ef, .probabilities = .{ 0x3fe0000000000000, 0x3fe0000000000000, 0x0000000000000000, 0x0000000000000000 } },
    .{ .len = 3, .inputs = .{ 0x3ff0000000000000, 0x4000000000000000, 0x4008000000000000, 0x0000000000000000 }, .lse_bits = 0x400b42c6ea778b93, .probabilities = .{ 0x3fb70c3e5f682bda, 0x3fcf534335ca4bcf, 0x3fe549a766a06791, 0x0000000000000000 } },
    .{ .len = 3, .inputs = .{ 0x408f400000000000, 0x408f480000000000, 0x408f500000000000, 0x0000000000000000 }, .lse_bits = 0x408f5342c6ea778c, .probabilities = .{ 0x3fb70c3e5f682bda, 0x3fcf534335ca4bcf, 0x3fe549a766a06791, 0x0000000000000000 } },
    .{ .len = 3, .inputs = .{ 0xc08f400000000000, 0xc08f380000000000, 0xc08f300000000000, 0x0000000000000000 }, .lse_bits = 0xc08f2cbd39158874, .probabilities = .{ 0x3fb70c3e5f682bda, 0x3fcf534335ca4bcf, 0x3fe549a766a06791, 0x0000000000000000 } },
    .{ .len = 4, .inputs = .{ 0x4008000000000000, 0x4008000000000000, 0x4008000000000000, 0x4008000000000000 }, .lse_bits = 0x40118b90bfbe8e7c, .probabilities = .{ 0x3fd0000000000000, 0x3fd0000000000000, 0x3fd0000000000000, 0x3fd0000000000000 } },
    .{ .len = 3, .inputs = .{ 0x4059000000000000, 0x0000000000000000, 0xc059000000000000, 0x0000000000000000 }, .lse_bits = 0x4059000000000000, .probabilities = .{ 0x3ff0000000000000, 0x36ea8c1f14e2af5d, 0x2de6061812054cfa, 0x0000000000000000 } },
    .{ .len = 2, .inputs = .{ 0x01a56e1fc2f8f359, 0x81a56e1fc2f8f359, 0x0000000000000000, 0x0000000000000000 }, .lse_bits = 0x3fe62e42fefa39ef, .probabilities = .{ 0x3fe0000000000000, 0x3fe0000000000000, 0x0000000000000000, 0x0000000000000000 } },
    .{ .len = 2, .inputs = .{ 0x4086280000000000, 0xc086280000000000, 0x0000000000000000, 0x0000000000000000 }, .lse_bits = 0x4086280000000000, .probabilities = .{ 0x3ff0000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 } },
    .{ .len = 4, .inputs = .{ 0x412e848000000000, 0x412e847e00000000, 0x412e847c00000000, 0x412e847a00000000 }, .lse_bits = 0x412e8480e1608b4f, .probabilities = .{ 0x3fe49af213f4b34a, 0x3fce522d1a571a02, 0x3fb64f170f077b9a, 0x3fa069fc39496c2a } },
};
