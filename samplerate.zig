const std = @import("std");

/// User supplied callback function type for use with src_callback_new()
/// and src_callback_read(). First parameter is the same pointer that was
/// passed into src_callback_new(). Second parameter is pointer to a
/// pointer. The user supplied callback function must modify *data to
/// point to the start of the user supplied float array. The user supplied
/// function must return the number of frames that **data points to.
pub const Callback = ?*const fn (*anyopaque, *[*]f32) callconv(.C) c_long;
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

const error_list = [_]Error {
	Error.MallocFailed,
	Error.BadState,
	Error.BadData,
	Error.BadDataPtr,
	Error.NoPrivate,
	Error.BadRatio,
	Error.BadProcPtr,
	Error.ShiftBits,
	Error.FilterLen,
	Error.BadConverter,
	Error.BadChannelCount,
	Error.SincBadBufferLen,
	Error.SizeIncompatibility,
	Error.BadPrivPtr,
	Error.BadSincState,
	Error.DataOverlap,
	Error.BadCallback,
	Error.BadMode,
	Error.NullCallback,
	Error.NoVariableRatio,
	Error.SincPrepareDataBadLen,
	Error.BadInternalState,
};

fn toError(i: c_uint) Error {
	return error_list[i - err_offset];
}

pub const Converter = enum(c_uint) {
	sinc_best,
	sinc_medium,
	sinc_fast,
	zero_order_hold,
	linear,

	const lo = @intFromEnum(Converter.sinc_best);
	const hi = @intFromEnum(Converter.linear);
	pub fn expectValid(i: c_uint) Error!void {
		if (i < lo or hi < i) {
			return Error.BadConverter;
		}
	}
};

pub const Data = extern struct {
	/// set by caller, pointer to the input data samples
	data_in: [*]const f32,
	/// set by caller, pointer to the output data samples
	data_out: [*]f32,
	/// set by caller, number of input frames
	input_frames: c_long,
	/// set by caller, max number of output frames
	output_frames: c_long,
	/// number of input frames consumed
	input_frames_used: c_long,
	/// number of output frames generated
	output_frames_gen: c_long,
	/// set by caller and internally, 0 if more input data is available
	end_of_input: c_int,
	/// set by caller, output_sample_rate / input_sample_rate
	src_ratio: f64,

	/// Simple interface for performing a single conversion from input buffer to
	/// output buffer at a fixed conversion ratio.
	/// Simple interface does not require initialisation as it can only operate on
	/// a single buffer worth of audio.
	pub fn simple(self: *Data, conv: Converter, chans: c_uint) Error!void {
		const result = src_simple(self, conv, chans);
		return if (result == success) {} else toError(result);
	}
	extern fn src_simple(*Data, Converter, c_uint) c_uint;
};

pub const State = opaque {
	/// Return an error. Mainly useful for callback based API.
	pub fn getError(self: *State) Error {
		return toError(src_error(self));
	}
	extern fn src_error(*State) c_uint;

	/// Standard initialisation function : return an anonymous pointer to the
	/// internal state of the converter. Choose a converter from the enums below.
	pub fn new(conv: Converter, channels: c_uint) Error!*State {
		var result: c_uint = undefined;
		return if (src_new(conv, channels, &result)) |s| s else toError(result);
	}
	extern fn src_new(Converter, c_uint, *c_uint) ?*State;

	/// Clone a handle : return an anonymous pointer to a new converter
	/// containing the same internal state as orig.
	pub fn clone(self: *State) Error!*State {
		var result: c_uint = undefined;
		return if (src_clone(self, &result)) |s| s else toError(result);
	}
	extern fn src_clone(*State, *c_uint) ?*State;

	/// Initilisation for callback based API : return an anonymous pointer to the
	/// internal state of the converter. Choose a converter from the enums below.
	/// The cb_data pointer can point to any data or be set to null. Whatever the
	/// value, when processing, user supplied function "func" gets called with
	/// cb_data as first parameter.
	pub fn callbackNew(
		func: Callback,
		conv: Converter,
		chans: c_uint,
		cb_data: ?*anyopaque,
	) Error!*State {
		var result: c_uint = undefined;
		return if (src_callback_new(func, conv, chans, &result, cb_data)) |s|
			s else toError(result);
	}
	extern fn src_callback_new(Callback, Converter, c_uint, *c_uint, ?*anyopaque) ?*State;

	/// Cleanup all internal allocations.
	pub fn delete(self: *State) void {
		_ = src_delete(self);
	}
	extern fn src_delete(*State) ?*State;

	/// Standard processing function.
	pub fn process(self: *State, data: *Data) Error!void {
		const result = src_process(self, data);
		return if (result == success) {} else toError(result);
	}
	extern fn src_process(*State, *Data) c_uint;

	/// Callback based processing function. Read up to frames worth of data from
	/// the converter int *data and return frames read or error.
	pub fn callbackRead(
		self: *State,
		ratio: f64,
		frames: c_ulong,
		data: [*]f32,
	) !c_ulong {
		const result = src_callback_read(self, ratio, frames, data);
		return if (result != 0) result else self.getError();
	}
	extern fn src_callback_read(*State, f64, c_ulong, [*]f32) c_ulong;

	/// Set a new SRC ratio. This allows step responses in the conversion ratio.
	pub fn setRatio(self: *State, new_ratio: f64) Error!void {
		const result = src_set_ratio(self, new_ratio);
		return if (result == success) {} else toError(result);
	}
	extern fn src_set_ratio(*State, f64) c_uint;

	/// Get the current channel count.
	pub fn getChannels(self: *State) Error!c_uint {
		const result = src_get_channels(self);
		return if (result >= 0) @intCast(result) else toError(-result);
	}
	extern fn src_get_channels(*State) c_int;

	/// Reset the internal SRC state.
	/// Does not modify the quality settings.
	/// Does not free any memory allocations.
	pub fn reset(self: *State) Error!void {
		const result = src_reset(self);
		return if (result == success) {} else toError(result);
	}
	extern fn src_reset(*State) c_uint;
};

/// Return the name of a sample rate converter
/// or null if no sample rate converter exists for the given value.
pub const getName = src_get_name;
extern fn src_get_name(Converter) ?[*:0]const u8;

/// Return the description of a sample rate converter
/// or null if no sample rate converter exists for the given value.
pub const getDescription = src_get_description;
extern fn src_get_description(Converter) ?[*:0]const u8;

pub const getVersion = src_get_version;
extern fn src_get_version() [*:0]const u8;

/// Convert the error number into a string.
pub fn strError(err: Error) ?[*:0]const u8 {
	for (0..error_list.len) |i| {
		if (error_list[i] == err) {
			return src_strerror(@intCast(i + err_offset));
		}
	}
	return null;
}
extern fn src_strerror(c_uint) ?[*:0]const u8;

pub fn isValidRatio(ratio: f64) bool {
	return (src_is_valid_ratio(ratio) != 0);
}
extern fn src_is_valid_ratio(ratio: f64) c_uint;

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
	const in16 = [_]i16{ -0x1p15, -0x1p8,  0, 0x1p8,  0x1p15-1 };
	const in32 = [_]i32{ -0x1p31, -0x1p16, 0, 0x1p16, 0x1p31-1 };
	var out = [_]f32{ 0 } ** in16.len;
	intToFloat(i16, f32, &in16, &out);
	intToFloat(i32, f32, &in32, &out);
}

pub fn floatToInt(F: type, I: type, in: []const F, out: []I) void {
	comptime typeCheck(I, F);
	std.debug.assert(in.len == out.len);
	const max = 1 << (@bitSizeOf(I) - 1);
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
	var out16 = [_]i16{ 0 } ** in.len;
	var out32 = [_]i32{ 0 } ** in.len;
	floatToInt(f32, i16, &in, &out16);
	floatToInt(f32, i32, &in, &out32);
}
