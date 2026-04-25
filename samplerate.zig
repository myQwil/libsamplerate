const c = @import("cdef");
const std = @import("std");

pub const uint = @Int(.unsigned, @bitSizeOf(c_int) - 1);
pub const ulong = @Int(.unsigned, @bitSizeOf(c_long) - 1);

/// User supplied callback function type for use with src_callback_new()
/// and src_callback_read(). First parameter is the same pointer that was
/// passed into src_callback_new(). Second parameter is pointer to a
/// pointer. The user supplied callback function must modify *data to
/// point to the start of the user supplied float array. The user supplied
/// function must return the number of frames that **data points to.
pub const Callback = fn (?*anyopaque, *[*]f32) callconv(.c) c_long;

const success = 0;
const err_offset = 1;

pub const Error = error {
	MallocFailed,
	BadState,
	BadData,
	BadDataPtr,
	NoPrivate,
	BadRatio,
	BadProcPtr,
	ShiftBits,
	FilterLen,
	BadConverter,
	BadChannelCount,
	SincBadBufferLen,
	SizeIncompatibility,
	BadPrivPtr,
	BadSincState,
	DataOverlap,
	BadCallback,
	BadMode,
	NullCallback,
	NoVariableRatio,
	SincPrepareDataBadLen,
	BadInternalState,
};

const error_list = [_]Error{
	error.MallocFailed,
	error.BadState,
	error.BadData,
	error.BadDataPtr,
	error.NoPrivate,
	error.BadRatio,
	error.BadProcPtr,
	error.ShiftBits,
	error.FilterLen,
	error.BadConverter,
	error.BadChannelCount,
	error.SincBadBufferLen,
	error.SizeIncompatibility,
	error.BadPrivPtr,
	error.BadSincState,
	error.DataOverlap,
	error.BadCallback,
	error.BadMode,
	error.NullCallback,
	error.NoVariableRatio,
	error.SincPrepareDataBadLen,
	error.BadInternalState,
};

fn toError(i: c_int) Error {
	return error_list[@as(usize, @intCast(i)) - err_offset];
}

pub const Converter = enum(uint) {
	sinc_best = 0,
	sinc_medium = 1,
	sinc_fast = 2,
	zero_order_hold = 3,
	linear = 4,

	const lo = @intFromEnum(Converter.sinc_best);
	const hi = @intFromEnum(Converter.linear);
	pub fn expectValid(i: uint) error{BadConverter}!void {
		if (i < lo or hi < i) {
			return error.BadConverter;
		}
	}
};

pub const Data = extern struct {
	/// set by caller, pointer to the input data samples
	data_in: [*]const f32,
	/// set by caller, pointer to the output data samples
	data_out: [*]f32,
	/// set by caller, number of input frames
	input_frames: c_ulong = 0,
	/// set by caller, max number of output frames
	output_frames: c_ulong = 0,
	/// number of input frames consumed
	input_frames_used: c_ulong = 0,
	/// number of output frames generated
	output_frames_gen: c_ulong = 0,
	/// set by caller and internally, 0 if more input data is available
	end_of_input: c_uint = 0,
	/// set by caller, output_sample_rate / input_sample_rate
	src_ratio: f64 = 1,

	/// Simple interface for performing a single conversion from input buffer to
	/// output buffer at a fixed conversion ratio.
	/// Simple interface does not require initialisation as it can only operate on
	/// a single buffer worth of audio.
	pub fn simple(self: *Data, conv: Converter, chans: uint) Error!void {
		const result = c.src_simple(@ptrCast(self), @intFromEnum(conv), chans);
		if (result != success) {
			return toError(result);
		}
	}
};

pub const State = opaque {
	/// Return an error. Mainly useful for callback based API.
	pub inline fn getError(self: *State) Error {
		return toError(c.src_error(@ptrCast(self)));
	}

	/// Standard initialisation function : return an anonymous pointer to the
	/// internal state of the converter. Choose a converter from the enums below.
	pub fn init(conv: Converter, channels: uint) Error!*State {
		var result: c_int = undefined;
		return if (c.src_new(@intFromEnum(conv), channels, &result)) |s|
			@ptrCast(s)
		else toError(result);
	}

	/// Clone a handle : return an anonymous pointer to a new converter
	/// containing the same internal state as orig.
	pub fn clone(self: *State) Error!*State {
		var result: c_int = undefined;
		return if (c.src_clone(@ptrCast(self), &result)) |s|
			@ptrCast(s)
		else toError(result);
	}

	/// Initilisation for callback based API : return an anonymous pointer to the
	/// internal state of the converter. Choose a converter from the enums below.
	/// The cb_data pointer can point to any data or be set to null. Whatever the
	/// value, when processing, user supplied function "func" gets called with
	/// cb_data as first parameter.
	pub fn callbackNew(
		func: ?*const Callback,
		conv: Converter,
		chans: uint,
		cb_data: ?*anyopaque,
	) Error!*State {
		var result: c_int = undefined;
		const state = c.src_callback_new(
			@ptrCast(func), @intFromEnum(conv), chans, &result, cb_data);
		return if (state) |s| @ptrCast(s) else toError(result);
	}

	/// Cleanup all internal allocations.
	pub fn deinit(self: *State) void {
		_ = c.src_delete(@ptrCast(self)); // returns null
	}

	/// Standard processing function.
	pub fn process(self: *State, data: *Data) Error!void {
		const result = c.src_process(@ptrCast(self), @ptrCast(data));
		if (result != success) {
			return toError(result);
		}
	}

	/// Callback based processing function. Read up to frames worth of data from
	/// the converter int *data and return frames read or error.
	pub fn callbackRead(self: *State, ratio: f64, data: []f32) Error!ulong {
		const result = c.src_callback_read(
			@ptrCast(self), ratio, @intCast(data.len), data.ptr);
		return if (result != 0) @intCast(result) else self.getError();
	}

	/// Set a new SRC ratio. This allows step responses in the conversion ratio.
	pub fn setRatio(self: *State, ratio: f64) Error!void {
		const result = c.src_set_ratio(@ptrCast(self), ratio);
		if (result != success) {
			return toError(result);
		}
	}

	/// Get the current channel count.
	pub fn getChannels(self: *State) Error!uint {
		const result = c.src_get_channels(@ptrCast(self));
		return if (result >= 0) @intCast(result) else toError(-result);
	}

	/// Reset the internal SRC state.
	/// Does not modify the quality settings.
	/// Does not free any memory allocations.
	pub fn reset(self: *State) Error!void {
		const result = c.src_reset(@ptrCast(self));
		if (result != success) {
			return toError(result);
		}
	}
};

/// Return the name of a sample rate converter
/// or null if no sample rate converter exists for the given value.
pub fn getName(conv: Converter) ?[*:0]const u8 {
	return c.src_get_name(@intFromEnum(conv));
}

/// Return the description of a sample rate converter
/// or null if no sample rate converter exists for the given value.
pub fn getDescription(conv: Converter) ?[*:0]const u8 {
	return c.src_get_description(@intFromEnum(conv));
}

pub fn getVersion() [*:0]const u8 {
	return c.src_get_version();
}

/// Convert the error number into a string.
pub fn strError(err: Error) ?[*:0]const u8 {
	for (0..error_list.len) |i| {
		if (error_list[i] == err) {
			return c.src_strerror(@intCast(i + err_offset));
		}
	}
	return null;
}

pub fn isValidRatio(ratio: f64) bool {
	return (c.src_is_valid_ratio(ratio) != 0);
}

fn typeCheck(I: type, F: type) void {
	const info = @typeInfo(I);
	if (info != .int or info.int.signedness != .signed)
		@compileError("`I` must be a signed integer type");
	if (@typeInfo(F) != .float)
		@compileError("`F` must be a floating point type");
}

pub fn intToFloat(I: type, F: type, in: []const I, out: []F) void {
	comptime typeCheck(I, F);
	std.debug.assert(in.len == out.len);
	const frac = 1.0 / @as(F, @floatFromInt(1 << (@bitSizeOf(I) - 1)));
	for (in, out) |int, *float| {
		float.* = @as(F, @floatFromInt(int)) * frac;
	}
}

test intToFloat {
	const in = [_]i32{ -0x1p31, -0x1p16, 0, 0x1p16, 0x1p31-1 };
	var out = [_]f64{ 0 } ** in.len;
	intToFloat(i32, f64, &in, &out);
	try std.testing.expectEqual(out[0], -1);
	try std.testing.expectEqual(out[4], 0.9999999995343387);
}

pub fn floatToInt(F: type, I: type, in: []const F, out: []I) void {
	comptime typeCheck(I, F);
	std.debug.assert(in.len == out.len);
	const max: comptime_float = 1 << (@bitSizeOf(I) - 1);
	for (in, out) |float, *int| {
		const scaled_value = float * max;
		int.* = if (scaled_value >= (max - 1))
			(max - 1)
		else if (scaled_value <= -max)
			-max
		else
			@intFromFloat(@round(scaled_value));
	}
}

test floatToInt {
	const in = [_]f32{ -1, -0x1p-10, 0, 0x1p-10, 1 };
	var out = [_]i32{ 0 } ** in.len;
	floatToInt(f32, i32, &in, &out);
	try std.testing.expectEqual(out[0], std.math.minInt(i32));
	try std.testing.expectEqual(out[4], std.math.maxInt(i32));
}
