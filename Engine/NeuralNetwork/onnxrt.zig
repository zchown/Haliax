const std = @import("std");

pub const ort = @cImport({
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
        const api = ort.OrtGetApiBase().?.GetApi(ort.ORT_API_VERSION).?;

        var env: *ort.OrtEnv = undefined;
        if (api.CreateEnv.? (ort.ORT_LOGGING_LEVEL_WARNING, "tak", &env) != ort.ORT_OK) {
            return error.OrtCreateEnvFailed;
        }
        errdefer _ = api.ReleaseEnv.?(env);

        var so: *ort.OrtSessionOptions = undefined;
        if (api.CreateSessionOptions.?(&so) != ort.ORT_OK) return error.OrtCreateSessionOptionsFailed;
        errdefer _ = api.ReleaseSessionOptions.?(so);

        _ = api.SetIntraOpNumThreads.?(so, 1);
        _ = api.SetGraphOptimizationLevel.?(so, ort.ORT_ENABLE_ALL);

        var mp_z = try allocator.allocSentinel(u8, model_path.len, 0);
        defer allocator.free(mp_z);
        @memcpy(mp_z[0..model_path.len], model_path);

        var session: *ort.OrtSession = undefined;
        if (api.CreateSession.?(env, mp_z.ptr, so, &session) != ort.ORT_OK) {
            return error.OrtCreateSessionFailed;
        }
        errdefer _ = api.ReleaseSession.?(session);

        var meminfo: *ort.OrtMemoryInfo = undefined;
        if (api.CreateCpuMemoryInfo.?(ort.OrtArenaAllocator, ort.OrtMemTypeDefault, &meminfo) != ort.ORT_OK) {
            return error.OrtCreateMemoryInfoFailed;
        }
        errdefer _ = api.ReleaseMemoryInfo.?(meminfo);

        const input_name = try getInputName(allocator, api, session, 0);
        errdefer allocator.free(input_name);

        var outs: [7][:0]const u8 = undefined;
        outs[0] = try getOutputName(allocator, api, session, 0);
        outs[1] = try getOutputName(allocator, api, session, 1);
        outs[2] = try getOutputName(allocator, api, session, 2);
        outs[3] = try getOutputName(allocator, api, session, 3);
        outs[4] = try getOutputName(allocator, api, session, 4);
        outs[5] = try getOutputName(allocator, api, session, 5);
        outs[6] = try getOutputName(allocator, api, session, 6);

        return .{
            .allocator = allocator,
            .api = api,
            .env = env,
            .session = session,
            .session_options = so,
            .meminfo = meminfo,
            .input_name = input_name,
            .output_names = outs,
        };
    }

    pub fn deinit(self: *OnnxRunner) void {
        self.allocator.free(self.input_name);
        for (self.output_names) |n| self.allocator.free(n);

        _ = self.api.ReleaseMemoryInfo.?(self.meminfo);
        _ = self.api.ReleaseSession.?(self.session);
        _ = self.api.ReleaseSessionOptions.?(self.session_options);
        _ = self.api.ReleaseEnv.?(self.env);
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

        var input_value: *ort.OrtValue = undefined;
        if (self.api.CreateTensorWithDataAsOrtValue.?(
            self.meminfo,
            @constCast(input_chw.ptr),
            input_chw.len * @sizeOf(f32),
            &shape,
            shape.len,
            ort.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &input_value,
        ) != ort.ORT_OK) return error.OrtCreateTensorFailed;
        defer _ = self.api.ReleaseValue.?(input_value);

        var output_values: [7]*ort.OrtValue = undefined;
        @memset(&output_values, null);

        const input_names = [_][*:0]const u8{ self.input_name.ptr };
        var output_names_c: [7][*:0]const u8 = undefined;
        for (self.output_names, 0..) |n, i| output_names_c[i] = n.ptr;

        if (self.api.Run.?(
            self.session,
            null,
            &input_names,
            @ptrCast(&input_value),
            1,
            &output_names_c,
            7,
            &output_values,
        ) != ort.ORT_OK) return error.OrtRunFailed;
        defer {
            for (output_values) |v| {
                if (v != null) _ = self.api.ReleaseValue.?(v);
            }
        }

        try copyOutF32(self, output_values[0], out_place_pos);
        try copyOutF32(self, output_values[1], out_place_type);
        try copyOutF32(self, output_values[2], out_slide_from);
        try copyOutF32(self, output_values[3], out_slide_dir);
        try copyOutF32(self, output_values[4], out_slide_pickup);
        try copyOutF32(self, output_values[5], out_slide_len);

        var value_buf: [1]f32 = undefined;
        try copyOutF32(self, output_values[6], value_buf[0..]);
        return value_buf[0];
    }
};

fn copyOutF32(self: *OnnxRunner, v: *ort.OrtValue, out: []f32) !void {
    var p: ?*anyopaque = null;
    if (self.api.GetTensorMutableData.?(v, &p) != ort.ORT_OK) return error.OrtGetTensorDataFailed;
    const src: [*]const f32 = @ptrCast(p.?);
    @memcpy(out, src[0..out.len]);
}

fn getInputName(allocator: std.mem.Allocator, api: *const ort.OrtApi, session: *ort.OrtSession, idx: usize) ![:0]const u8 {
    var allocator_ort: *ort.OrtAllocator = undefined;
    if (api.GetAllocatorWithDefaultOptions.?(&allocator_ort) != ort.ORT_OK) return error.OrtAllocatorFailed;

    var name_ptr: [*:0]u8 = undefined;
    if (api.SessionGetInputName.?(session, @intCast(idx), allocator_ort, &name_ptr) != ort.ORT_OK) return error.OrtGetNameFailed;
    defer _ = allocator_ort.Free.?(allocator_ort, name_ptr);

    return try allocator.dupeZ(u8, std.mem.span(name_ptr));
}

fn getOutputName(allocator: std.mem.Allocator, api: *const ort.OrtApi, session: *ort.OrtSession, idx: usize) ![:0]const u8 {
    var allocator_ort: *ort.OrtAllocator = undefined;
    if (api.GetAllocatorWithDefaultOptions.?(&allocator_ort) != ort.ORT_OK) return error.OrtAllocatorFailed;

    var name_ptr: [*:0]u8 = undefined;
    if (api.SessionGetOutputName.?(session, @intCast(idx), allocator_ort, &name_ptr) != ort.ORT_OK) return error.OrtGetNameFailed;
    defer _ = allocator_ort.Free.?(allocator_ort, name_ptr);

    return try allocator.dupeZ(u8, std.mem.span(name_ptr));
}

