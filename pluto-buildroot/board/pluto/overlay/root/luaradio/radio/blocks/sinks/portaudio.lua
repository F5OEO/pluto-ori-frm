---
-- Sink one or more real-valued signals to the system's audio device with
-- PortAudio. This sink requires the PortAudio library.
--
-- @category Sinks
-- @block PortAudioSink
-- @tparam int num_channels Number of channels (e.g. 1 for mono, 2 for stereo)
--
-- @signature in:Float32 >
-- @signature in1:Float32, in2:Float32, ... >
--
-- @usage
-- -- Sink to one channel (mono) audio
-- local snk = radio.PortAudioSink(1)
-- top:connect(src, snk)
--
-- -- Sink to two channel (stereo) audio
-- local snk = radio.PortAudioSink(2)
-- top:connect(src_left, 'out', snk, 'in1')
-- top:connect(src_right, 'out', snk, 'in2')

local ffi = require('ffi')

local platform = require('radio.core.platform')
local block = require('radio.core.block')
local types = require('radio.types')

local PortAudioSink = block.factory("PortAudioSink")

function PortAudioSink:instantiate(num_channels)
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

if not package.loaded['radio.blocks.sources.portaudio'] then
    ffi.cdef[[
        typedef void PaStream;

        typedef int PaError;
        typedef int PaDeviceIndex;
        typedef int PaHostApiIndex;
        typedef double PaTime;
        typedef unsigned long PaSampleFormat;
        typedef unsigned long PaStreamFlags;
        typedef struct PaStreamCallbackTimeInfo PaStreamCallbackTimeInfo;
        typedef unsigned long PaStreamCallbackFlags;
        typedef int PaStreamCallback(const void *input, void *output, unsigned long frameCount, const PaStreamCallbackTimeInfo *timeInfo, PaStreamCallbackFlags statusFlags, void *userData);

        enum { paFramesPerBufferUnspecified = 0 };
        enum { paFloat32 = 0x00000001 };

        PaError Pa_Initialize(void);
        PaError Pa_Terminate(void);

        PaError Pa_OpenDefaultStream(PaStream **stream, int numInputChannels, int numOutputChannels, PaSampleFormat sampleFormat, double sampleRate, unsigned long framesPerBuffer, PaStreamCallback *streamCallback, void *userData);
        PaError Pa_StartStream(PaStream *stream);
        PaError Pa_WriteStream(PaStream *stream, const void *buffer, unsigned long frames);
        PaError Pa_ReadStream(PaStream *stream, void *buffer, unsigned long frames);
        PaError Pa_StopStream(PaStream *stream);
        PaError Pa_CloseStream(PaStream *stream);

        const char *Pa_GetErrorText(PaError errorCode);
    ]]
end
local libportaudio_available, libportaudio = platform.load({"portaudio", "libportaudio.so.2"})

function PortAudioSink:initialize()
    -- Check library is available
    if not libportaudio_available then
        error("PortAudioSink: libportaudio not found. Is PortAudio installed?")
    end
end

function PortAudioSink:initialize_portaudio()
    -- Initialize PortAudio
    local err = libportaudio.Pa_Initialize()
    if err ~= 0 then
        error("Pa_Initialize(): " .. ffi.string(libportaudio.Pa_GetErrorText(err)))
    end

    -- Open default stream
    self.stream = ffi.new("PaStream *[1]")
    local err = libportaudio.Pa_OpenDefaultStream(self.stream, 0, self.num_channels, ffi.C.paFloat32, self:get_rate(), ffi.C.paFramesPerBufferUnspecified, nil, nil)
    if err ~= 0 then
        error("Pa_OpenDefaultStream(): " .. ffi.string(libportaudio.Pa_GetErrorText(err)))
    end

    -- Start the stream
    local err = libportaudio.Pa_StartStream(self.stream[0])
    if err ~= 0 then
        error("Pa_StartStream(): " .. ffi.string(libportaudio.Pa_GetErrorText(err)))
    end
end

function PortAudioSink:process(...)
    local samples = {...}

    -- Initialize PortAudio in our own running process
    if not self.stream then
        self:initialize_portaudio()
    end

    local interleaved_samples
    if self.num_channels == 1 then
        interleaved_samples = samples[1]
    else
        -- Interleave samples
        interleaved_samples = types.Float32.vector(self.num_channels*samples[1].length)
        for i = 0, samples[1].length-1 do
            for j = 0, self.num_channels-1 do
                interleaved_samples.data[i*self.num_channels + j] = samples[j+1].data[i]
            end
        end
    end

    -- Write to our PortAudio connection
    local err = libportaudio.Pa_WriteStream(self.stream[0], interleaved_samples.data, samples[1].length)
    if err ~= 0 then
        error("Pa_WriteStream(): " .. ffi.string(libportaudio.Pa_GetErrorText(err)))
    end
end

function PortAudioSink:cleanup()
    -- If we never got around to creating a stream
    if not self.stream then
        return
    end

    -- Stop the stream
    local err = libportaudio.Pa_StopStream(self.stream[0])
    if err ~= 0 then
        error("Pa_StopStream(): " .. ffi.string(libportaudio.Pa_GetErrorText(err)))
    end

    -- Close the stream
    local err = libportaudio.Pa_CloseStream(self.stream[0])
    if err ~= 0 then
        error("Pa_StopStream(): " .. ffi.string(libportaudio.Pa_GetErrorText(err)))
    end

    -- Terminate PortAudio
    local err = libportaudio.Pa_Terminate()
    if err ~= 0 then
        error("Pa_Terminate(): " .. ffi.string(libportaudio.Pa_GetErrorText(err)))
    end
end

return PortAudioSink
