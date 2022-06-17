---
-- Frequency discriminate a complex-valued signal. This is a method of
-- frequency demodulation.
--
-- $$ y[n] = \frac{\text{arg}(x[n] \; x^*[n-1])}{2 \pi k} $$
--
-- @category Demodulation
-- @block FrequencyDiscriminatorBlock
-- @tparam number modulation_index Modulation index (Carrier Deviation / Maximum Modulation Frequency)
--
-- @signature in:ComplexFloat32 > out:Float32
--
-- @usage
-- -- Frequency discriminator with modulation index 1.25
-- local fm_demod = radio.FrequencyDiscriminatorBlock(1.25)

local ffi = require('ffi')

local platform = require('radio.core.platform')
local block = require('radio.core.block')
local types = require('radio.types')

local FrequencyDiscriminatorBlock = block.factory("FrequencyDiscriminatorBlock")

function FrequencyDiscriminatorBlock:instantiate(modulation_index)
    assert(modulation_index, "Missing argument #1 (modulation_index)")

    self.gain = 2*math.pi*modulation_index

    self:add_type_signature({block.Input("in", types.ComplexFloat32)}, {block.Output("out", types.Float32)})
end

function FrequencyDiscriminatorBlock:initialize()
    self.prev_sample = types.ComplexFloat32()

    self.tmp = types.ComplexFloat32.vector()
    self.out = types.Float32.vector()
end

if platform.features.volk then

    ffi.cdef[[
    void (*volk_32fc_x2_multiply_conjugate_32fc)(complex_float32_t* cVector, const complex_float32_t* aVector, const complex_float32_t* bVector, unsigned int num_points);
    void (*volk_32fc_s32f_atan2_32f_a)(float32_t* outputVector, const complex_float32_t* complexVector, const float normalizeFactor, unsigned int num_points);
    ]]
    local libvolk = platform.libs.volk

    function FrequencyDiscriminatorBlock:process(x)
        local tmp = self.tmp:resize(x.length)
        local out = self.out:resize(x.length)

        -- Multiply element-wise of samples by conjugate of previous samples
        --      [a b c d e f g h] * ~[p a b c d e f g]
        tmp.data[0] = x.data[0]*self.prev_sample:conj()
        libvolk.volk_32fc_x2_multiply_conjugate_32fc(tmp.data[1], x.data[1], x.data, x.length-1)

        -- Compute element-wise atan2 of multiplied samples
        libvolk.volk_32fc_s32f_atan2_32f_a(out.data, tmp.data, self.gain, x.length)

        -- Save last sample of x to be the next previous sample
        self.prev_sample = types.ComplexFloat32(x.data[x.length-1].real, x.data[x.length-1].imag)

        return out
    end

else

    function FrequencyDiscriminatorBlock:process(x)
        local tmp = self.tmp:resize(x.length)
        local out = self.out:resize(x.length)

        -- Multiply element-wise of samples by conjugate of previous samples
        --      [a b c d e f g h] * ~[p a b c d e f g]
        tmp.data[0] = x.data[0]*self.prev_sample:conj()
        for i = 1, x.length-1 do
            tmp.data[i] = x.data[i] * x.data[i-1]:conj()
        end

        -- Compute element-wise atan2 of multiplied samples
        for i = 0, tmp.length-1 do
            out.data[i].value = tmp.data[i]:arg()*(1/self.gain)
        end

        -- Save last sample of x to be the next previous sample
        self.prev_sample = types.ComplexFloat32(x.data[x.length-1].real, x.data[x.length-1].imag)

        return out
    end

end

return FrequencyDiscriminatorBlock
