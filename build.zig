const std = @import("std");
const LinkMode = std.builtin.LinkMode;

const Options = struct {
	linkage: LinkMode = .static,

	fn init(b: *std.Build) Options {
		const default: Options = .{};
		return .{
			.linkage = b.option(LinkMode, "linkage",
				"Library linking method"
			) orelse default.linkage,
		};
	}
};

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});
	const opt: Options = .init(b);

	//---------------------------------------------------------------------------
	// Library
	const lib = blk: {
		const upstream = b.dependency("libsamplerate", .{});

		const mod = b.createModule(.{
			.target = target,
			.optimize = optimize,
			.link_libc = true,
		});
		mod.addCSourceFiles(.{
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
		mod.addIncludePath(upstream.path("include"));

		const lib = b.addLibrary(.{
			.name = "samplerate",
			.linkage = opt.linkage,
			.root_module = mod,
		});
		b.installArtifact(lib);
		break :blk lib;
	};

	//---------------------------------------------------------------------------
	// Zig module
	const zig_mod = b.addModule("samplerate", .{
		.root_source_file = b.path("samplerate.zig"),
		.target = target,
		.optimize = optimize,
	});
	zig_mod.linkLibrary(lib);
}
