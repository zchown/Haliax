const std = @import("std");

pub const ort = @cImport({
    @cDefine("ORT_API_MANUAL_INIT", "1");
    @cInclude("onnxruntime_c_api.h");
});

pub const OnnxRunner = struct {
    allocator: std.mem.Allocator,

    api: *const ort.OrtApi,
    env: *ort.OrtEnv,
    session: *ort.OrtSession,
    session_options: *ort.OrtSessionOptions,
    meminfo: *ort.OrtMemoryInfo,

    input_name: [:0]const u8,
    output_names: [7][:0]const u8,

    pub fn init(allocator: std.mem.Allocator, model_path: []const u8) !OnnxRunner {
        // Match the style that works in Zig (unwrap the optional function pointer GetApi with .?)
        const api_c = ort.OrtGetApiBase().*.GetApi.?(ort.ORT_API_VERSION);

        // api_c is usually imported as a C pointer ([*c]const OrtApi). Convert to *const OrtApi.
        // (This is the same “trust it’s non-null” assumption the wrapper makes.)
        const api: *const ort.OrtApi = @ptrCast(@alignCast(api_c));

        var env: ?*ort.OrtEnv = null;
        try checkStatus(api, api.CreateEnv.?(ort.ORT_LOGGING_LEVEL_WARNING, "tak", &env));
        errdefer api.ReleaseEnv.?(env.?);

        var so: ?*ort.OrtSessionOptions = null;
        try checkStatus(api, api.CreateSessionOptions.?(&so));
        errdefer api.ReleaseSessionOptions.?(so.?);

        // These return OrtStatus* (null on success); ignore failures here only if you want,
        // but it's better to check.
        try checkStatus(api, api.SetIntraOpNumThreads.?(so.?, 1));
        try checkStatus(api, api.SetSessionGraphOptimizationLevel.?(so.?, ort.ORT_ENABLE_ALL));

        // CreateSession wants a null-terminated path.
        var mp_z = try allocator.allocSentinel(u8, model_path.len, 0);
        defer allocator.free(mp_z);
        @memcpy(mp_z[0..model_path.len], model_path);

        var session: ?*ort.OrtSession = null;
        try checkStatus(api, api.CreateSession.?(env.?, mp_z.ptr, so.?, &session));
        errdefer api.ReleaseSession.?(session.?);

        var meminfo: ?*ort.OrtMemoryInfo = null;
        try checkStatus(api, api.CreateCpuMemoryInfo.?(ort.OrtArenaAllocator, ort.OrtMemTypeDefault, &meminfo));
        errdefer api.ReleaseMemoryInfo.?(meminfo.?);

        const input_name = try getInputName(allocator, api, session.?, 0);
        errdefer allocator.free(input_name);

        var outs: [7][:0]const u8 = undefined;
        inline for (0..7) |i| {
            outs[i] = try getOutputName(allocator, api, session.?, i);
        }
        errdefer for (outs) |n| allocator.free(n);

        return .{
            .allocator = allocator,
            .api = api,
            .env = env.?,
            .session = session.?,
            .session_options = so.?,
            .meminfo = meminfo.?,
            .input_name = input_name,
            .output_names = outs,
        };
    }

    pub fn deinit(self: *OnnxRunner) void {
        self.allocator.free(self.input_name);
        for (self.output_names) |n| self.allocator.free(n);

        // Do not return from defer blocks; just release.
        self.api.ReleaseMemoryInfo.?(self.meminfo);
        self.api.ReleaseSession.?(self.session);
        self.api.ReleaseSessionOptions.?(self.session_options);
        self.api.ReleaseEnv.?(self.env);
    }

    pub fn run(
        self: *OnnxRunner,
        channels_in: i64,
        input_chw: []const f32, // len = channels_in*36
        out_place_pos: []f32,   // 36
        out_place_type: []f32,  // 3
        out_slide_from: []f32,  // 36
        out_slide_dir: []f32,   // 4
        out_slide_pickup: []f32,// 6
        out_slide_len: []f32,   // 6
    ) !f32 {
        if (input_chw.len != @as(usize, @intCast(channels_in * 36))) return error.BadInputLen;

        var shape: [4]i64 = .{ 1, channels_in, 6, 6 };

        var input_value: ?*ort.OrtValue = null;
        try checkStatus(self.api, self.api.CreateTensorWithDataAsOrtValue.?(
            self.meminfo,
            // ORT wants a void*, we have *const f32.
            @ptrCast(@constCast(input_chw.ptr)),
            input_chw.len * @sizeOf(f32),
            &shape,
            shape.len,
            ort.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &input_value,
        ));
        defer self.api.ReleaseValue.?(input_value.?);

        // Use optional pointers for outputs so "null" is representable correctly.
        var output_values: [7]?*ort.OrtValue = .{null} ** 7;

        const input_names = [_][*:0]const u8{ self.input_name.ptr };
        const input_values = [_]*ort.OrtValue{ input_value.? };

        var output_names_c: [7][*:0]const u8 = undefined;
        for (self.output_names, 0..) |n, i| output_names_c[i] = n.ptr;

        // Signature in Zig cimport typically matches this calling pattern.
        try checkStatus(self.api, self.api.Run.?(
            self.session,
            null,
            input_names[0..].ptr,
            input_values[0..].ptr,
            input_values.len,
            output_names_c[0..].ptr,
            output_values.len,
            output_values[0..].ptr,
        ));

        defer {
            for (output_values) |ov| {
                if (ov) |v| self.api.ReleaseValue.?(v);
            }
        }

        try copyOutF32(self.api, output_values[0] orelse return error.MissingOutput0, out_place_pos);
        try copyOutF32(self.api, output_values[1] orelse return error.MissingOutput1, out_place_type);
        try copyOutF32(self.api, output_values[2] orelse return error.MissingOutput2, out_slide_from);
        try copyOutF32(self.api, output_values[3] orelse return error.MissingOutput3, out_slide_dir);
        try copyOutF32(self.api, output_values[4] orelse return error.MissingOutput4, out_slide_pickup);
        try copyOutF32(self.api, output_values[5] orelse return error.MissingOutput5, out_slide_len);

        var value_buf: [1]f32 = undefined;
        try copyOutF32(self.api, output_values[6] orelse return error.MissingOutput6, value_buf[0..]);
        return value_buf[0];
    }
};

fn copyOutF32(api: *const ort.OrtApi, v: *ort.OrtValue, out: []f32) !void {
    var p: ?*anyopaque = null;
    try checkStatus(api, api.GetTensorMutableData.?(v, &p));

    const raw = p orelse return error.OrtNullTensorData;

    // Assert the pointer is aligned for f32 before treating it as f32*
    const aligned: *align(@alignOf(f32)) anyopaque = @alignCast(raw);
    const src: [*]const f32 = @ptrCast(aligned);

    @memcpy(out, src[0..out.len]);
}

fn getInputName(
    allocator: std.mem.Allocator,
    api: *const ort.OrtApi,
    session: *ort.OrtSession,
    idx: usize,
) ![:0]const u8 {
    var allocator_ort: ?*ort.OrtAllocator = null;
    try checkStatus(api, api.GetAllocatorWithDefaultOptions.?(&allocator_ort));

    // IMPORTANT: match the exact C signature: char*
    var name_ptr: [*c]u8 = null;
    try checkStatus(api, api.SessionGetInputName.?(
        session,
        @intCast(idx),
        allocator_ort.?,
        &name_ptr,
    ));

    const free_fn = allocator_ort.?.Free orelse return error.OrtAllocatorMissingFree;
    defer free_fn(allocator_ort.?, name_ptr);

    // Convert returned C string to Zig sentinel slice
    return try allocator.dupeZ(u8, std.mem.span(@as([*:0]u8, @ptrCast(name_ptr))));
}

fn getOutputName(
    allocator: std.mem.Allocator,
    api: *const ort.OrtApi,
    session: *ort.OrtSession,
    idx: usize,
) ![:0]const u8 {
    var allocator_ort: ?*ort.OrtAllocator = null;
    try checkStatus(api, api.GetAllocatorWithDefaultOptions.?(&allocator_ort));

    var name_ptr: [*c]u8 = null;
    try checkStatus(api, api.SessionGetOutputName.?(
        session,
        @intCast(idx),
        allocator_ort.?,
        &name_ptr,
    ));

    const free_fn = allocator_ort.?.Free orelse return error.OrtAllocatorMissingFree;
    defer free_fn(allocator_ort.?, name_ptr);

    return try allocator.dupeZ(u8, std.mem.span(@as([*:0]u8, @ptrCast(name_ptr))));
}

fn checkStatus(api: *const ort.OrtApi, status: ?*ort.OrtStatus) !void {
    if (status == null) return;
    defer api.ReleaseStatus.?(status);

    const msg = api.GetErrorMessage.?(status);
    std.log.err("ONNX Runtime error: {s}", .{msg});

    return error.OnnxError;
}

