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

	const upstream = b.dependency("libsamplerate", .{});

	//---------------------------------------------------------------------------
	// Library
	const lib = blk: {
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
	const c_mod = blk: {
		const c = b.addTranslateC(.{
			.root_source_file = upstream.path("include/samplerate.h"),
			.target = target,
			.optimize = optimize,
		});
		break :blk c.createModule();
	};
	const zig_mod = b.addModule("samplerate", .{
		.root_source_file = b.path("samplerate.zig"),
		.target = target,
		.optimize = optimize,
		.imports = &.{ .{ .name = "cdef", .module = c_mod } },
	});
	zig_mod.linkLibrary(lib);

	//---------------------------------------------------------------------------
	// Zig example
	const exe = b.addExecutable(.{
		.name = "hello",
		.root_module = b.createModule(.{
			.root_source_file = b.path("examples/hello.zig"),
			.target = target,
			.optimize = optimize,
			.imports = &.{ .{ .name = "rabbit", .module = zig_mod } },
		}),
	});

	const install = b.addInstallArtifact(exe, .{});
	const step_install = b.step("hello", "Build the zig example");
	step_install.dependOn(&install.step);

	const run = b.addRunArtifact(exe);
	run.step.dependOn(&install.step);
	const step_run = b.step("run_hello", "Build and run the zig example");
	step_run.dependOn(&run.step);
	// if (b.args) |args| {
		// run.addArgs(args);
	// }
}
