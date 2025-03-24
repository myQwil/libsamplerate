const std = @import("std");
const LinkMode = std.builtin.LinkMode;

const Options = struct {
	linkage: LinkMode = .static,
};

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const defaults = Options{};
	const opt = Options{
		.linkage = b.option(LinkMode, "linkage", "Library linking method")
			orelse defaults.linkage,
	};

	const lib = b.addLibrary(.{
		.name = "samplerate",
		.linkage = opt.linkage,
		.root_module = b.createModule(.{
			.target = target,
			.optimize = optimize,
			.link_libc = true,
		}),
	});

	const upstream = b.dependency("libsamplerate", .{});
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
	lib.addIncludePath(upstream.path("include"));
	b.installArtifact(lib);

	const mod = b.addModule("samplerate", .{
		.root_source_file = b.path("samplerate.zig"),
		.target = target,
		.optimize = optimize,
	});
	mod.linkLibrary(lib);
}
