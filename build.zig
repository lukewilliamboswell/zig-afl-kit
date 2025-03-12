const std = @import("std");

pub fn addInstrumentedExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// Pass null if llvm-config is in PATH
    llvm_config_path: ?[]const []const u8,
    /// If true will search the path for afl++ instead of compiling from source.
    /// This is a workaround for issues with zig compiled afl++ and C++11 abi on ubuntu.
    use_system_afl: bool,
    obj: *std.Build.Step.Compile,
) ?std.Build.LazyPath {
    const afl_kit = b.dependencyFromBuildZig(@This(), .{});

    std.debug.assert(obj.root_module.stack_check == false); // not linking with compiler-rt
    std.debug.assert(obj.root_module.link_libc == true); // afl runtime depends on libc
    std.debug.assert(obj.sanitize_coverage_trace_pc_guard == true); // must have zig instrument the binary (or instrumentation fails on macos)

    var run_afl_cc: *std.Build.Step.Run = undefined;
    if (!use_system_afl) {
        const afl = afl_kit.builder.lazyDependency("AFLplusplus", .{
            .target = target,
            .optimize = optimize,
            .@"llvm-config-path" = llvm_config_path orelse &[_][]const u8{},
        }) orelse return null;

        const install_tools = b.addInstallDirectory(.{
            .source_dir = std.Build.LazyPath{
                .cwd_relative = afl.builder.install_path,
            },
            .install_dir = .prefix,
            .install_subdir = "AFLplusplus",
        });

        install_tools.step.dependOn(afl.builder.getInstallStep());
        run_afl_cc = b.addSystemCommand(&.{
            b.pathJoin(&.{ afl.builder.exe_dir, "afl-cc" }),
            "-O3",
            "-o",
        });
        run_afl_cc.step.dependOn(&afl.builder.top_level_steps.get("llvm_exes").?.step);
        run_afl_cc.step.dependOn(&install_tools.step);
    } else {
        run_afl_cc = b.addSystemCommand(&.{
            b.findProgram(&.{"afl-cc"}, &.{}) catch @panic("Could not find 'afl-cc', which is required to build"),
            "-O3",
            "-o",
        });
    }
    const fuzz_exe = run_afl_cc.addOutputFileArg(obj.name);
    run_afl_cc.addFileArg(afl_kit.path("afl.c"));
    run_afl_cc.addFileArg(obj.getEmittedBin());
    return fuzz_exe;
}

pub fn build(b: *std.Build) !void {
    _ = b;
    // const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

}
