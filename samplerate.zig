const std = @import("std");

/// User supplied callback function type for use with src_callback_new()
/// and src_callback_read(). First parameter is the same pointer that was
/// passed into src_callback_new(). Second parameter is pointer to a
/// pointer. The user supplied callback function must modify *data to
/// point to the start of the user supplied float array. The user supplied
/// function must return the number of frames that **data points to.
pub const Callback = ?*const fn (*anyopaque, *[*]f32) callconv(.C) c_long;
const success = 0;

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

const Result = c_int;

fn toError(i: Result) Error {
	return error_list[@as(u32, @intCast(i)) - 1];
}

pub const Converter = enum(c_uint) {
	sinc_best,
	sinc_medium,
	sinc_fast,
	zero_order_hold,
	linear,

	const lo = @intFromEnum(Converter.sinc_best);
	const hi = @intFromEnum(Converter.linear);
	pub fn expectValid(i: u32) Error!void {
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
	pub fn simple(self: *Data, conv: Converter, chans: u32) Error!void {
		const result = src_simple(self, conv, chans);
		return if (result == success) {} else toError(result);
	}
	extern fn src_simple(*Data, Converter, c_uint) Result;
};

pub const State = opaque {
	/// Return an error. Mainly useful for callback based API.
	pub fn getError(self: *State) Error {
		return toError(@intCast(src_error(self)));
	}
	extern fn src_error(*State) c_int;

	/// Standard initialisation function : return an anonymous pointer to the
	/// internal state of the converter. Choose a converter from the enums below.
	pub fn new(conv: Converter, chans: u32) Error!*State {
		var result: Result = undefined;
		return if (src_new(conv, @intCast(chans), &result)) |s| s else toError(result);
	}
	extern fn src_new(Converter, c_int, *Result) ?*State;

	/// Clone a handle : return an anonymous pointer to a new converter
	/// containing the same internal state as orig.
	pub fn clone(self: *State) Error!*State {
		var result: Result = undefined;
		return if (src_clone(self, &result)) |s| s else toError(result);
	}
	extern fn src_clone(*State, *Result) ?*State;

	/// Initilisation for callback based API : return an anonymous pointer to the
	/// internal state of the converter. Choose a converter from the enums below.
	/// The cb_data pointer can point to any data or be set to null. Whatever the
	/// value, when processing, user supplied function "func" gets called with
	/// cb_data as first parameter.
	pub fn callbackNew(
		func: Callback,
		conv: Converter,
		chans: u32,
		cb_data: ?*anyopaque,
	) Error!*State {
		var result: Result = undefined;
		return if (src_callback_new(func, conv, chans, &result, cb_data)) |s|
			s else toError(result);
	}
	extern fn src_callback_new(Callback, Converter, c_uint, *Result, ?*anyopaque) ?*State;

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
	extern fn src_process(*State, *Data) Result;

	/// Callback based processing function. Read up to frames worth of data from
	/// the converter int *data and return frames read or error.
	pub fn callbackRead(self: *State, ratio: f64, frames: usize, data: *f32) !usize {
		const result = src_callback_read(self, ratio, @intCast(frames), data);
		return if (result > 0) @intCast(result) else self.getError();
	}
	extern fn src_callback_read(*State, f64, c_long, *f32) c_long;

	/// Set a new SRC ratio. This allows step responses in the conversion ratio.
	pub fn setRatio(self: *State, new_ratio: f64) Error!void {
		const result = src_set_ratio(self, new_ratio);
		return if (result == success) {} else toError(result);
	}
	extern fn src_set_ratio(*State, f64) Result;

	/// Get the current channel count.
	pub fn getChannels(self: *State) Error!u32 {
		const result = src_get_channels(self);
		return if (result >= 0) @intCast(result) else toError(-result);
	}
	extern fn src_get_channels(*State) Result;

	/// Reset the internal SRC state.
	/// Does not modify the quality settings.
	/// Does not free any memory allocations.
	pub fn reset(self: *State) Error!void {
		const result = src_reset(self);
		return if (result == success) {} else toError(result);
	}
	extern fn src_reset(*State) Result;
};

/// Return the name of a sample rate converter
/// or null if no sample rate converter exists for the given value.
pub fn getName(conv: Converter) ?[:0]const u8 {
	const str = src_get_name(conv);
	return if (str) |s| s[0..std.mem.len(s)] else null;
}
extern fn src_get_name(Converter) ?[*:0]const u8;

/// Return the description of a sample rate converter
/// or null if no sample rate converter exists for the given value.
pub fn getDescription(conv: Converter) ?[:0]const u8 {
	const str = src_get_description(conv);
	return if (str) |s| s[0..std.mem.len(s)] else null;
}
extern fn src_get_description(Converter) ?[*:0]const u8;

pub fn getVersion() [:0]const u8 {
	const s = src_get_version();
	return s[0..std.mem.len(s)];
}
extern fn src_get_version() [*:0]const u8;

/// Convert the error number into a string.
pub fn strError(err: Error) ?[:0]const u8 {
	for (0..error_list.len) |i| {
		if (error_list[i] == err) {
			return if (src_strerror(@intCast(i + 1))) |s| s[0..std.mem.len(s) :0] else null;
		}
	}
	return null;
}
extern fn src_strerror(Result) ?[*:0]const u8;

pub fn isValidRatio(ratio: f64) bool {
	return (src_is_valid_ratio(ratio) != 0);
}
extern fn src_is_valid_ratio(ratio: f64) c_int;

pub fn shortToFloat(in: [*]const i16, out: [*]f32, len: usize) void {
	src_short_to_float_array(in, out, @intCast(len));
}
extern fn src_short_to_float_array(in: [*]const c_short, out: [*]f32, len: c_int) void;

pub fn floatToShort(in: [*]const f32, out: [*]i16, len: usize) void {
	src_float_to_short_array(in, out, @intCast(len));
}
extern fn src_float_to_short_array(in: [*]const f32, out: [*]c_short, len: c_int) void;

pub fn intToFloat(in: [*]const i32, out: [*]f32, len: usize) void {
	src_int_to_float_array(in, out, @intCast(len));
}
extern fn src_int_to_float_array(in: [*]const c_int, out: [*]f32, len: c_int) void;

pub fn floatToInt(in: [*]const f32, out: [*]i32, len: usize) void {
	src_float_to_int_array(in, out, @intCast(len));
}
extern fn src_float_to_int_array(in: [*]const f32, out: [*]c_int, len: c_int) void;
