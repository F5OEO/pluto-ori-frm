---
-- Source a complex-valued signal from an RTL-SDR dongle. This source requires
-- the librtlsdr library.
--
-- @category Sources
-- @block RtlSdrSource
-- @tparam number frequency Tuning frequency in Hz
-- @tparam number rate Sample rate in Hz
-- @tparam[opt={}] table options Additional options, specifying:
--      * `biastee` (bool, default false)
--      * `direct_sampling` (string, default "disabled", choice of "disabled", "i", "q")
--      * `bandwidth` (number, default equal to sample rate)
--      * `autogain` (bool, default true if manual gain is nil)
--      * `rf_gain` (number in dB, manual gain, default nil)
--      * `freq_correction` PPM (number, default 0.0)
--      * `device_index` (integer, default 0)
--
-- @signature > out:ComplexFloat32
--
-- @usage
-- -- Source samples from 162.400 MHz sampled at 1 MHz, with autogain enabled
-- local src = radio.RtlSdrSource(162.400e6, 1e6, {autogain = true})
--
-- -- Source samples from 91.1 MHz sampled at 1.102500 MHz, with -1 PPM correction
-- local src = radio.RtlSdrSource(91.1e6, 1102500, {freq_correction = -1.0})
--
-- -- Source samples from 144.390 MHz sampled at 1 MHz, with RF gain of 15dB
-- local src = radio.RtlSdrSource(144.390e6, 1e6, {rf_gain = 15.0})

local ffi = require('ffi')

local block = require('radio.core.block')
local platform = require('radio.core.platform')
local pipe = require('radio.core.pipe')
local types = require('radio.types')
local debug = require('radio.core.debug')

local RtlSdrSource = block.factory("RtlSdrSource")

function RtlSdrSource:instantiate(frequency, rate, options)
    self.frequency = assert(frequency, "Missing argument #1 (frequency)")
    self.rate = assert(rate, "Missing argument #2 (rate)")

    self.options = options or {}
    self.biastee = self.options.biastee or false
    self.direct_sampling = self.options.direct_sampling or "disabled"
    self.bandwidth = self.options.bandwidth or 0.0
    self.rf_gain = self.options.rf_gain or nil
    self.autogain = (self.rf_gain == nil) and true or self.options.autogain
    self.freq_correction = self.options.freq_correction or 0.0
    self.device_index = self.options.device_index or 0

    assert(self.direct_sampling == "disabled" or self.direct_sampling == "i" or self.direct_sampling == "q", string.format("Invalid direct sampling mode, should be \"disabled\", \"i\", or \"q\"."))

    self:add_type_signature({}, {block.Output("out", types.ComplexFloat32)})
end

function RtlSdrSource:get_rate()
    return self.rate
end

ffi.cdef[[
    typedef struct rtlsdr_dev rtlsdr_dev_t;

    const char* rtlsdr_get_device_name(uint32_t index);
    int rtlsdr_get_usb_strings(rtlsdr_dev_t *dev, char *manufact, char *product, char *serial);

    int rtlsdr_open(rtlsdr_dev_t **dev, uint32_t index);
    int rtlsdr_close(rtlsdr_dev_t *dev);

    int rtlsdr_set_sample_rate(rtlsdr_dev_t *dev, uint32_t rate);
    int rtlsdr_set_center_freq(rtlsdr_dev_t *dev, uint32_t freq);
    int rtlsdr_set_tuner_gain_mode(rtlsdr_dev_t *dev, int manual);
    int rtlsdr_set_agc_mode(rtlsdr_dev_t *dev, int on);
    int rtlsdr_set_tuner_gain(rtlsdr_dev_t *dev, int gain);
    int rtlsdr_set_tuner_if_gain(rtlsdr_dev_t *dev, int stage, int gain);
    int rtlsdr_set_freq_correction(rtlsdr_dev_t *dev, int ppm);
    int rtlsdr_get_tuner_gains(rtlsdr_dev_t *dev, int *gains);
    int rtlsdr_set_tuner_bandwidth(rtlsdr_dev_t *dev, uint32_t bw);
    int rtlsdr_set_direct_sampling(rtlsdr_dev_t *dev, int on);
    int rtlsdr_set_bias_tee(rtlsdr_dev_t *dev, int on);

    int rtlsdr_reset_buffer(rtlsdr_dev_t *dev);

    typedef void(*rtlsdr_read_async_cb_t)(unsigned char *buf, uint32_t len, void *ctx);
    int rtlsdr_read_async(rtlsdr_dev_t *dev, rtlsdr_read_async_cb_t cb, void *ctx, uint32_t buf_num, uint32_t buf_len);
    int rtlsdr_cancel_async(rtlsdr_dev_t *dev);
]]
local librtlsdr_available, librtlsdr = pcall(ffi.load, "rtlsdr")

function RtlSdrSource:initialize()
    -- Check library is available
    if not librtlsdr_available then
        error("RtlSdrSource: librtlsdr not found. Is librtlsdr installed?")
    end
end

function RtlSdrSource:initialize_rtlsdr()
    self.dev = ffi.new("rtlsdr_dev_t *[1]")

    local ret

    -- Open device
    ret = librtlsdr.rtlsdr_open(self.dev, self.device_index)
    if ret ~= 0 then
        error("rtlsdr_open(): " .. tostring(ret))
    end

    -- Dump device info
    if debug.enabled then
        -- Look up device name
        local device_name = ffi.string(librtlsdr.rtlsdr_get_device_name(self.device_index))

        -- Look up USB device strings
        local usb_manufacturer = ffi.new("char[256]")
        local usb_product = ffi.new("char[256]")
        local usb_serial = ffi.new("char[256]")
        ret = librtlsdr.rtlsdr_get_usb_strings(self.dev[0], usb_manufacturer, usb_product, usb_serial)
        if ret ~= 0 then
            error("rtlsdr_get_usb_strings(): " .. tostring(ret))
        end
        usb_manufacturer = ffi.string(usb_manufacturer)
        usb_product = ffi.string(usb_product)
        usb_serial = ffi.string(usb_serial)

        debug.printf("[RtlSdrSource] Device name:       %s\n", device_name)
        debug.printf("[RtlSdrSource] USB Manufacturer:  %s\n", usb_manufacturer)
        debug.printf("[RtlSdrSource] USB Product:       %s\n", usb_product)
        debug.printf("[RtlSdrSource] USB Serial:        %s\n", usb_serial)
    end

    -- Turn on bias tee if required, ignore if not required
    if self.biastee then
        -- Turn on bias tee
        ret = librtlsdr.rtlsdr_set_bias_tee(self.dev[0], 1)
        if ret ~= 0 then
            error("rtlsdr_set_bias_tee(): " .. tostring(ret))
        end
    end

    if self.direct_sampling ~= "disabled" then
        -- Set direct sampling mode
        ret = librtlsdr.rtlsdr_set_direct_sampling(self.dev[0], ({i = 1, q = 2})[self.direct_sampling])
        if ret ~= 0 then
            error("rtlsdr_set_direct_sampling(): " .. tostring(ret))
        end
    end

    if self.autogain then
        -- Set autogain
        ret = librtlsdr.rtlsdr_set_tuner_gain_mode(self.dev[0], 0)
        if ret ~= 0 then
            error("rtlsdr_set_tuner_gain_mode(): " .. tostring(ret))
        end

        -- Enable AGC
        ret = librtlsdr.rtlsdr_set_agc_mode(self.dev[0], 1)
        if ret ~= 0 then
            error("rtlsdr_set_agc_mode(): " .. tostring(ret))
        end
    else
        -- Disable autogain
        ret = librtlsdr.rtlsdr_set_tuner_gain_mode(self.dev[0], 1)
        if ret ~= 0 then
            error("rtlsdr_set_tuner_gain_mode(): " .. tostring(ret))
        end

        -- Disable AGC
        ret = librtlsdr.rtlsdr_set_agc_mode(self.dev[0], 0)
        if ret ~= 0 then
            error("rtlsdr_set_agc_mode(): " .. tostring(ret))
        end

        -- Set RF gain
        ret = librtlsdr.rtlsdr_set_tuner_gain(self.dev[0], math.floor(self.rf_gain*10))
        if ret ~= 0 then
            error("rtlsdr_set_tuner_gain(): " .. tostring(ret))
        end
    end

    debug.printf("[RtlSdrSource] Frequency: %u Hz, Sample rate: %u Hz\n", self.frequency, self.rate)

    -- Set frequency correction
    local ret = librtlsdr.rtlsdr_set_freq_correction(self.dev[0], math.floor(self.freq_correction))
    if ret ~= 0 and ret ~= -2 then
        error("rtlsdr_set_freq_correction(): " .. tostring(ret))
    end

    -- Set frequency
    ret = librtlsdr.rtlsdr_set_center_freq(self.dev[0], self.frequency)
    if ret ~= 0 then
        error("rtlsdr_set_center_freq(): " .. tostring(ret))
    end

    -- Set sample rate
    ret = librtlsdr.rtlsdr_set_sample_rate(self.dev[0], self.rate)
    if ret ~= 0 then
        error("rtlsdr_set_sample_rate(): " .. tostring(ret))
    end

    -- Set bandwidth
    ret = librtlsdr.rtlsdr_set_tuner_bandwidth(self.dev[0], self.bandwidth)
    if ret ~= 0 then
        error("rtlsdr_set_tuner_bandwidth(): " .. tostring(ret))
    end

    -- Reset endpoint buffer
    ret = librtlsdr.rtlsdr_reset_buffer(self.dev[0])
    if ret ~= 0 then
        error("rtlsdr_reset_buffer(): " .. tostring(ret))
    end
end

function RtlSdrSource:run()
    -- Initialize the rtlsdr in our own running process
    self:initialize_rtlsdr()

    -- Create output vector
    local out = types.ComplexFloat32.vector()

    -- Create pipe mux
    local pipe_mux = pipe.PipeMux({}, {self.outputs[1].pipes}, self.control_socket)

    local read_callback = function (buf, len, ctx)
        -- Resize output vector
        out:resize(len/2)

        -- Convert complex u8 in buf to complex floats in output vector
        for i = 0, out.length-1 do
            out.data[i].real = (buf[2*i]   - 127.5) * (1/127.5)
            out.data[i].imag = (buf[2*i+1] - 127.5) * (1/127.5)
        end

        -- Write output vector to output pipes
        local eof, eof_pipe, shutdown = pipe_mux:write({out})

        -- Check for downstream EOF or control socket shutdown
        if shutdown then
            librtlsdr.rtlsdr_cancel_async(self.dev[0])
        elseif eof then
            librtlsdr.rtlsdr_cancel_async(self.dev[0])
            io.stderr:write(string.format("[%s] Downstream block %s terminated unexpectedly.\n", self.name, eof_pipe.input.owner.name))
        end
    end

    -- Start asynchronous read (blocking)
    local ret = librtlsdr.rtlsdr_read_async(self.dev[0], read_callback, nil, 0, 32768)
    if ret ~= 0 then
        error("rtlsdr_read_async(): " .. tostring(ret))
    end

    -- Turn off bias tee if it was enabled, ignore if not required
    if self.biastee then
        -- Turn off bias tee
        ret = librtlsdr.rtlsdr_set_bias_tee(self.dev[0], 0)
        if ret ~= 0 then
            error("rtlsdr_set_bias_tee(): " .. tostring(ret))
        end
    end

    -- Close rtlsdr
    ret = librtlsdr.rtlsdr_close(self.dev[0])
    if ret ~= 0 then
        error("rtlsdr_close(): " .. tostring(ret))
    end
end

return RtlSdrSource
