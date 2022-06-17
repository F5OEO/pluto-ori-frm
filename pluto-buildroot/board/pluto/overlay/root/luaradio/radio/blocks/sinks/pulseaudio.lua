---
-- Sink one or more real-valued signals to the system's audio device with
-- PulseAudio. This sink requires PulseAudio.
--
-- @category Sinks
-- @block PulseAudioSink
-- @tparam int num_channels Number of channels (e.g. 1 for mono, 2 for stereo)
--
-- @signature in:Float32 >
-- @signature in1:Float32, in2:Float32, ... >
--
-- @usage
-- -- Sink to one channel (mono) audio
-- local snk = radio.PulseAudioSink(1)
-- top:connect(src, snk)
--
-- -- Sink to two channel (stereo) audio
-- local snk = radio.PulseAudioSink(2)
-- top:connect(src_left, 'out', snk, 'in1')
-- top:connect(src_right, 'out', snk, 'in2')

local ffi = require('ffi')

local platform = require('radio.core.platform')
local block = require('radio.core.block')
local types = require('radio.types')

local PulseAudioSink = block.factory("PulseAudioSink")

function PulseAudioSink:instantiate(num_channels)
    self.num_channels = assert(num_channels, "Missing argument #1 (num_channels)")

    if self.num_channels == 1 then
        self:add_type_signature({block.Input("in", types.Float32)}, {})
    else
        local block_inputs = {}
        for i = 1, self.num_channels do
            block_inputs[i] = block.Input("in" .. i, types.Float32)
        end
        self:add_type_signature(block_inputs, {})
    end
end

if not package.loaded['radio.blocks.sources.pulseaudio'] then
    ffi.cdef[[
        typedef struct pa_simple pa_simple;

        typedef enum pa_sample_format { PA_SAMPLE_FLOAT32LE = 5, PA_SAMPLE_FLOAT32BE = 6 } pa_sample_format_t;

        typedef struct pa_sample_spec {
            pa_sample_format_t format;
            uint32_t rate;
            uint8_t channels;
        } pa_sample_spec;
        typedef struct pa_buffer_attr pa_buffer_attr;
        typedef struct pa_channel_map pa_channel_map;

        typedef enum pa_stream_direction {
            PA_STREAM_NODIRECTION,
            PA_STREAM_PLAYBACK,
            PA_STREAM_RECORD,
            PA_STREAM_UPLOAD
        } pa_stream_direction_t;

        typedef struct pa_buffer_attr {
            uint32_t maxlength;
            uint32_t tlength;
            uint32_t prebuf;
            uint32_t minreq;
            uint32_t fragsize;
        } pa_buffer_attr;

        pa_simple* pa_simple_new(const char *server, const char *name, pa_stream_direction_t dir, const char *dev, const char *stream_name, const pa_sample_spec *ss, const pa_channel_map *map, const pa_buffer_attr *attr, int *error);

        void pa_simple_free(pa_simple *s);
        int pa_simple_write(pa_simple *s, const void *data, size_t bytes, int *error);
        int pa_simple_read(pa_simple *s, void *data, size_t bytes, int *error);

        const char* pa_strerror(int error);
    ]]
end
local libpulse_available, libpulse = platform.load({"pulse-simple", "libpulse-simple.so.0"})

function PulseAudioSink:initialize()
    -- Check library is available
    if not libpulse_available then
        error("PulseAudioSink: libpulse-simple not found. Is PulseAudio installed?")
    end

    -- Prepare sample spec
    self.sample_spec = ffi.new("pa_sample_spec")
    self.sample_spec.format = ffi.abi("le") and ffi.C.PA_SAMPLE_FLOAT32LE or ffi.C.PA_SAMPLE_FLOAT32BE
    self.sample_spec.channels = self.num_channels
    self.sample_spec.rate = self:get_rate()

    -- Create interleaved sample vector for multiple channels
    if self.num_channels > 1 then
        self.interleaved_samples = types.Float32.vector()
    end
end

function PulseAudioSink:initialize_pulseaudio()
    local error_code = ffi.new("int[1]")

    -- Open PulseAudio connection
    self.pa_conn = ffi.new("pa_simple *")
    self.pa_conn = libpulse.pa_simple_new(nil, "LuaRadio", ffi.C.PA_STREAM_PLAYBACK, nil, "PulseAudioSink", self.sample_spec, nil, nil, error_code)
    if self.pa_conn == nil then
        error("pa_simple_new(): " .. ffi.string(libpulse.pa_strerror(error_code[0])))
    end
end

function PulseAudioSink:process(...)
    local samples = {...}
    local error_code = ffi.new("int[1]")

    -- We can't fork with a PulseAudio connection, so we create it in our own
    -- running process
    if not self.pa_conn then
        self:initialize_pulseaudio()
    end

    local interleaved_samples
    if self.num_channels == 1 then
        interleaved_samples = samples[1]
    else
        -- Interleave samples
        interleaved_samples = self.interleaved_samples:resize(self.num_channels*samples[1].length)
        for i = 0, samples[1].length-1 do
            for j = 0, self.num_channels-1 do
                interleaved_samples.data[i*self.num_channels + j] = samples[j+1].data[i]
            end
        end
    end

    -- Write to our PulseAudio connection
    local ret = libpulse.pa_simple_write(self.pa_conn, interleaved_samples.data, interleaved_samples.size, error_code)
    if ret < 0 then
        error("pa_simple_write(): " .. ffi.string(libpulse.pa_strerror(error_code[0])))
    end
end

function PulseAudioSink:cleanup()
    -- If we never got around to creating a PulseAudio connection
    if not self.pa_conn then
        return
    end

    -- Close and free our PulseAudio connection
    libpulse.pa_simple_free(self.pa_conn)
end

return PulseAudioSink
