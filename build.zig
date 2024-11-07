const std = @import("std");

const Options = struct {
	shared: bool = false,
};

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const defaults = Options{};
	const opt = Options{
		.shared = b.option(bool, "shared", "Build shared library")
			orelse defaults.shared,
	};

	const upstream = b.dependency("libsamplerate", .{});
	const lib = if (opt.shared) b.addSharedLibrary(.{
		.name="samplerate", .target=target, .optimize=optimize, .pic=true,
	}) else b.addStaticLibrary(.{
		.name="samplerate", .target=target, .optimize=optimize,
	});
	lib.linkLibC();
	lib.addCSourceFiles(.{
		.root = upstream.path("src"),
		.files = &.{
			"samplerate.c",
			"src_linear.c",
			"src_sinc.c",
			"src_zoh.c",
		},
		.flags = &.{
			"-DENABLE_SINC_FAST_CONVERTER",
			"-DENABLE_SINC_MEDIUM_CONVERTER",
			"-DENABLE_SINC_BEST_CONVERTER",
			"-DHAVE_STDBOOL_H",
			"-DPACKAGE=\"libsamplerate\"",
			"-DVERSION=\"0.2.3\"",
		},
	});
	b.installArtifact(lib);

	const mod = b.addModule("samplerate", .{
		.root_source_file = b.path("samplerate.zig"),
		.target = target,
		.optimize = optimize,
	});
	mod.linkLibrary(lib);
}
