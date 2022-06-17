---
-- Filter a complex or real valued signal with a real-valued FIR band-stop
-- filter generated by the window design method.
--
-- $$ y[n] = (x * h_{bsf})[n] $$
--
-- @category Filtering
-- @block BandstopFilterBlock
-- @tparam int num_taps Number of FIR taps, must be odd
-- @tparam {number,number} cutoffs Cutoff frequencies in Hz
-- @tparam[opt=nil] number nyquist Nyquist frequency, if specifying
--                                 normalized cutoff frequencies
-- @tparam[opt='hamming'] string window Window type
--
-- @signature in:ComplexFloat32 > out:ComplexFloat32
-- @signature in:Float32 > out:Float32
--
-- @usage
-- -- Bandstop filter, 128 taps, 18 kHz to 20 kHz
-- local bpf = radio.BandstopFilterBlock(128, {18e3, 20e3})

local ffi = require('ffi')

local block = require('radio.core.block')
local types = require('radio.types')
local filter_utils = require('radio.utilities.filter_utils')

local FIRFilterBlock = require('radio.blocks.signal.firfilter')

local BandstopFilterBlock = block.factory("BandstopFilterBlock", FIRFilterBlock)

function BandstopFilterBlock:instantiate(num_taps, cutoffs, nyquist, window)
    assert(num_taps, "Missing argument #1 (num_taps)")
    self.cutoffs = assert(cutoffs, "Missing argument #2 (cutoffs)")
    self.window = window or "hamming"
    self.nyquist = nyquist

    FIRFilterBlock.instantiate(self, types.Float32.vector(num_taps))
end

function BandstopFilterBlock:initialize()
    -- Compute Nyquist frequency
    local nyquist = self.nyquist or (self:get_rate()/2)

    -- Generate taps
    local cutoffs = {self.cutoffs[1]/nyquist, self.cutoffs[2]/nyquist}
    local taps = filter_utils.firwin_bandstop(self.taps.length, cutoffs, self.window)
    self.taps = types.Float32.vector_from_array(taps)

    FIRFilterBlock.initialize(self)
end

return BandstopFilterBlock
