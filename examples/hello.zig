//! This is mainly just here to get ZLS to work properly.

const std = @import("std");
const ra = @import("rabbit");

pub fn main(_: std.process.Init) !void {
	const state: *ra.State = try .init(.linear, 2);
	defer state.deinit();
}
