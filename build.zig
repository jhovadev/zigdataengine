const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("zdata", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = module });
    const test_step = b.step("test", "Test all format-agnostic primitives");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const benchmark_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    benchmark_tests.root_module.addImport("zdata", module);
    test_step.dependOn(&b.addRunArtifact(benchmark_tests).step);

    const stats_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/stats.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(stats_tests).step);

    // M1.9: numeric benchmark tests and independent math/stats benchmark step.
    const numeric_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/numeric.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    numeric_tests.root_module.addImport("zdata", module);
    test_step.dependOn(&b.addRunArtifact(numeric_tests).step);

    const math_bench = b.addExecutable(.{
        .name = "zdata-math-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/numeric.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    math_bench.root_module.addImport("zdata", module);
    const math_bench_step = b.step("math-bench", "Benchmark numerical primitives with f128 accuracy checks");
    const math_bench_cmd = b.addRunArtifact(math_bench);
    math_bench_cmd.addPassthruArgs();
    math_bench_step.dependOn(&math_bench_cmd.step);

    // M1.7/M1.8: a build-time inventory of the installed Zig standard library.
    const math_audit = b.addExecutable(.{
        .name = "zdata-math-audit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/math_audit.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    math_audit.root_module.addImport("zdata", module);
    const audit_step = b.step("math-audit", "Inventory std.math features in this Zig version");
    audit_step.dependOn(&b.addRunArtifact(math_audit).step);

    // M1.8: hermetic accuracy report against committed high-precision vectors.
    const accuracy = b.addExecutable(.{
        .name = "zdata-math-accuracy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/math/accuracy_report.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    accuracy.root_module.addImport("zdata", module);
    const accuracy_step = b.step("math-accuracy", "Compare math primitives to mpmath golden vectors");
    accuracy_step.dependOn(&b.addRunArtifact(accuracy).step);

    const demo = b.addExecutable(.{
        .name = "zdata-copy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/copy_file.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo.root_module.addImport("zdata", module);
    b.installArtifact(demo);

    const run_step = b.step("run", "Copy a file: zig build run -- <source> <new-destination>");
    const run_cmd = b.addRunArtifact(demo);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    run_step.dependOn(&run_cmd.step);

    const bench = b.addExecutable(.{
        .name = "zdata-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench.root_module.addImport("zdata", module);
    const bench_step = b.step("bench", "Benchmark scanning and memory transfer");
    const bench_cmd = b.addRunArtifact(bench);
    bench_cmd.addPassthruArgs();
    bench_step.dependOn(&bench_cmd.step);
}
