---
-- Source one or more real-valued signals from a WAV file. The supported sample
-- formats are 8-bit unsigned integer, 16-bit signed integer, and 32-bit signed
-- integer.
--
-- @category Sources
-- @block WAVFileSource
-- @tparam string|file|int file Filename, file object, or file descriptor
-- @tparam int num_channels Number of channels (e.g. 1 for mono, 2 for stereo, etc.)
-- @tparam[opt=false] bool repeat_on_eof Repeat on end of file
--
-- @signature > out:Float32
-- @signature > out1:Float32, out2:Float32, ...
--
-- @usage
-- -- Source one channel WAV file
-- local src = radio.WAVFileSource('test.wav', 1)
--
-- -- Source two channel WAV file
-- local src = radio.WAVFileSource('test.wav', 2)
-- -- Compose the two channels into a complex-valued signal
-- top:connect(src, 'out1', floattocomplex, 'real')
-- top:connect(src, 'out2', floattocomplex, 'imag')
-- top:connect(floattocomplex, ..., snk)

local ffi = require('ffi')

local block = require('radio.core.block')
local vector = require('radio.core.vector')
local types = require('radio.types')
local format_utils = require('radio.utilities.format_utils')

local WAVFileSource = block.factory("WAVFileSource")

-- WAV File Headers and Samples
ffi.cdef[[
    typedef struct {
        char id[4];
        uint32_t size;
        char format[4];
    } riff_header_t;

    typedef struct {
        char id[4];
        uint32_t size;
        uint16_t audio_format;
        uint16_t num_channels;
        uint32_t sample_rate;
        uint32_t byte_rate;
        uint16_t block_align;
        uint16_t bits_per_sample;
    } wave_subchunk1_header_t;

    typedef struct {
        char id[4];
        uint32_t size;
    } wave_subchunk2_header_t;
]]

local wave_formats = {
    [8]     = format_utils.formats.u8,
    [16]    = format_utils.formats.s16le,
    [32]    = format_utils.formats.s32le,
}

function WAVFileSource:instantiate(file, num_channels, repeat_on_eof)
    if type(file) == "string" then
        self.filename = file
    elseif type(file) == "number" then
        self.fd = file
    else
        self.file = assert(file, "Missing argument #1 (file)")
    end

    self.num_channels = assert(num_channels, "Missing argument #2 (num_channels)")
    self.repeat_on_eof = repeat_on_eof or false

    self.rate = nil
    self.chunk_size = 8192

    -- Build type signature
    if num_channels == 1 then
        self:add_type_signature({}, {block.Output("out", types.Float32)})
    else
        local block_outputs = {}
        for i = 1, num_channels do
            block_outputs[#block_outputs+1] = block.Output("out" .. i, types.Float32)
        end
        self:add_type_signature({}, block_outputs)
    end
end

function WAVFileSource:get_rate()
    return self.rate
end

-- Header endianness conversion

local function bswap32(x)
    return bit.bswap(x)
end

local function bswap16(x)
    return bit.rshift(bit.bswap(x), 16)
end

local function bswap_riff_header(riff_header)
    riff_header.size = bswap32(riff_header.size)
end

local function bswap_wave_subchunk1_header(wave_subchunk1_header)
    wave_subchunk1_header.size = bswap32(wave_subchunk1_header.size)
    wave_subchunk1_header.audio_format = bswap16(wave_subchunk1_header.audio_format)
    wave_subchunk1_header.num_channels = bswap16(wave_subchunk1_header.num_channels)
    wave_subchunk1_header.sample_rate = bswap32(wave_subchunk1_header.sample_rate)
    wave_subchunk1_header.byte_rate = bswap32(wave_subchunk1_header.byte_rate)
    wave_subchunk1_header.block_align = bswap16(wave_subchunk1_header.block_align)
    wave_subchunk1_header.bits_per_sample = bswap16(wave_subchunk1_header.bits_per_sample)
end

local function bswap_wave_subchunk2_header(wave_subchunk2_header)
    wave_subchunk2_header.id = bswap32(wave_subchunk2_header.id)
    wave_subchunk2_header.size = bswap32(wave_subchunk2_header.size)
end

-- Initialization

function WAVFileSource:initialize()
    if self.filename then
        self.file = ffi.C.fopen(self.filename, "rb")
        if self.file == nil then
            error("fopen(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
    elseif self.fd then
        self.file = ffi.C.fdopen(self.fd, "rb")
        if self.file == nil then
            error("fdopen(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
    end

    -- Read headers
    self.riff_header = ffi.new("riff_header_t")
    if ffi.C.fread(self.riff_header, ffi.sizeof(self.riff_header), 1, self.file) ~= 1 then
        error("fread(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end
    self.wave_subchunk1_header = ffi.new("wave_subchunk1_header_t")
    if ffi.C.fread(self.wave_subchunk1_header, ffi.sizeof(self.wave_subchunk1_header), 1, self.file) ~= 1 then
        error("fread(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end
    self.wave_subchunk2_header = ffi.new("wave_subchunk2_header_t")
    if ffi.C.fread(self.wave_subchunk2_header, ffi.sizeof(self.wave_subchunk2_header), 1, self.file) ~= 1 then
        error("fread(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end

    -- Byte swap if needed for endianness
    if ffi.abi("be") then
        bswap_riff_header(self.riff_header)
        bswap_wave_subchunk1_header(self.wave_subchunk1_header)
        bswap_wave_subchunk2_header(self.wave_subchunk2_header)
    end

    -- Check RIFF header
    if ffi.string(self.riff_header.id, 4) ~= "RIFF" then
        error("Invalid WAV file: invalid RIFF header id.")
    end
    if ffi.string(self.riff_header.format, 4) ~= "WAVE" then
        error("Invalid WAV file: invalid RIFF header format.")
    end

    -- Check WAVE Subchunk 1 Header
    if ffi.string(self.wave_subchunk1_header.id, 4) ~= "fmt " then
        error("Invalid WAV file: invalid WAVE subchunk1 header id.")
    end
    if self.wave_subchunk1_header.audio_format ~= 1 then
        error(string.format("Unsupported WAV file: unsupported audio format %d (not PCM).", self.wave_subchunk1_header.audio_format))
    end
    if self.wave_subchunk1_header.num_channels ~= self.num_channels then
        error(string.format("Block number of channels (%d) does not match WAV file number of channels (%d).", self.num_channels, self.wave_subchunk1_header.num_channels))
    end
    if wave_formats[self.wave_subchunk1_header.bits_per_sample] == nil then
        error(string.format("Unsupported WAV file: unsupported bits per sample %d.", self.wave_subchunk1_header.bits_per_sample))
    end

    -- Check WAVE Subchunk 2 Header
    if ffi.string(self.wave_subchunk2_header.id, 4) ~= "data" then
        error("Invalid WAV file: invalid WAVE subchunk2 header id.")
    end

    -- Pull out sample rate and format
    self.rate = self.wave_subchunk1_header.sample_rate
    self.format = wave_formats[self.wave_subchunk1_header.bits_per_sample]

    -- Register open file
    self.files[self.file] = true

    -- Create sample vectors
    self.raw_samples = vector.Vector(self.format.real_ctype, self.chunk_size)
    self.out = {}
    for i = 1, self.num_channels do
        self.out[i] = types.Float32.vector()
    end
end

function WAVFileSource:process()
    -- Read from file
    local num_samples = tonumber(ffi.C.fread(self.raw_samples.data, ffi.sizeof(self.raw_samples.data_type), self.raw_samples.length, self.file))
    if num_samples < self.chunk_size then
        if num_samples == 0 and ffi.C.feof(self.file) ~= 0 then
            if self.repeat_on_eof then
                -- Rewind past header
                local header_length = ffi.sizeof("riff_header_t") + ffi.sizeof("wave_subchunk1_header_t") + ffi.sizeof("wave_subchunk2_header_t")
                if ffi.C.fseek(self.file, header_length, ffi.C.SEEK_SET) ~= 0 then
                    error("fseek(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
                end
            else
                return nil
            end
        else
            if ffi.C.ferror(self.file) ~= 0 then
                error("fread(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
            end
        end
    end

    -- Perform byte swap for endianness if needed
    if self.format.swap then
        for i = 0, num_samples-1 do
            format_utils.swap_bytes(self.raw_samples.data[i])
        end
    end

    -- Resize samples vector for each channel
    for i = 1, self.num_channels do
        self.out[i]:resize(num_samples/self.num_channels)
    end

    -- Convert raw samples to float32 samples for each channel
    for i = 0, (num_samples/self.num_channels)-1 do
        for j = 1, self.num_channels do
            self.out[j].data[i].value = (self.raw_samples.data[i*self.num_channels + (j-1)].value - self.format.offset)/self.format.scale
        end
    end

    return unpack(self.out)
end

function WAVFileSource:cleanup()
    if self.filename then
        if ffi.C.fclose(self.file) ~= 0 then
            error("fclose(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
    end
end

return WAVFileSource
