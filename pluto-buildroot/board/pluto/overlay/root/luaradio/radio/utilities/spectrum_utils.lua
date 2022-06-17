---
-- DFT, IDFT, PSD, and fftshift implementations.
--
-- @module radio.utilities.spectrum_utils

local ffi = require('ffi')
local math = require('math')

local platform = require('radio.core.platform')
local class = require('radio.core.class')
local types = require('radio.types')
local window_utils = require('radio.utilities.window_utils')

--------------------------------------------------------------------------------
-- DFT
--------------------------------------------------------------------------------

---
-- Discrete Fourier Transform class.
--
-- @internal
-- @class DFT
-- @tparam vector input_samples ComplexFloat32 or Float32 vector of input samples
-- @tparam vector output_samples ComplexFloat32 vector of output transformed samples
local DFT = class.factory()

function DFT.new(input_samples, output_samples)
    local self = setmetatable({}, DFT)

    if input_samples.data_type ~= types.ComplexFloat32 and input_samples.data_type ~= types.Float32 then
        error("Unsupported input samples data type.")
    elseif output_samples.data_type ~= types.ComplexFloat32 then
        error("Unsupported output samples data type.")
    elseif input_samples.length ~= output_samples.length then
        error("Input samples and output samples length mismatch.")
    elseif (input_samples.length % 2) ~= 0 then
        error("DFT length must be even.")
    end

    self.input_samples = input_samples
    self.output_samples = output_samples

    self.num_samples = self.input_samples.length
    self.data_type = self.input_samples.data_type

    -- Pick complex or real DFT
    if self.data_type == types.ComplexFloat32 then
        self.compute = self.compute_complex
    else
        self.compute = self.compute_real
    end

    -- Initialize the DFT
    self:initialize()

    return self
end

---
-- Compute the discrete fourier transform.
--
-- @internal
-- @function DFT:compute

--------------------------------------------------------------------------------
-- DFT implementations
--------------------------------------------------------------------------------

if platform.features.fftw3f then

    ffi.cdef[[
    typedef struct fftwf_plan_s *fftwf_plan;
    typedef float32_t fftwf_real;
    typedef complex_float32_t fftwf_complex;

    fftwf_plan fftwf_plan_dft_1d(int n, fftwf_complex *in, fftwf_complex *out, int sign, unsigned flags);
    fftwf_plan fftwf_plan_dft_r2c_1d(int n0, fftwf_real *in, fftwf_complex *out, unsigned flags);
    void fftwf_execute(const fftwf_plan plan);
    void fftwf_destroy_plan(fftwf_plan plan);

    enum { FFTW_FORWARD = -1, FFTW_BACKWARD = 1 };
    enum { FFTW_MEASURE = 0, FFTW_ESTIMATE = (1 << 6) };
    ]]
    local libfftw3f = platform.libs.fftw3f

    function DFT:initialize()
        -- Create plan
        if self.data_type == types.ComplexFloat32 then
            self.plan = ffi.gc(libfftw3f.fftwf_plan_dft_1d(self.num_samples, self.input_samples.data, self.output_samples.data, ffi.C.FFTW_FORWARD, ffi.C.FFTW_ESTIMATE), libfftw3f.fftwf_destroy_plan)
        else
            self.plan = ffi.gc(libfftw3f.fftwf_plan_dft_r2c_1d(self.num_samples, self.input_samples.data, self.output_samples.data, ffi.C.FFTW_ESTIMATE), libfftw3f.fftwf_destroy_plan)
        end

        if self.plan == nil then
            error("Creating FFTW plan.")
        end
    end

    function DFT:compute_complex()
        -- Execute FFTW plan
        libfftw3f.fftwf_execute(self.plan)
    end

    function DFT:compute_real()
        -- Execute FFTW plan
        libfftw3f.fftwf_execute(self.plan)

        -- Populate negative frequencies
        for k = math.floor(self.num_samples/2)+1, self.num_samples-1 do
            self.output_samples.data[k].real = self.output_samples.data[self.num_samples-k].real
            self.output_samples.data[k].imag = -self.output_samples.data[self.num_samples-k].imag
        end
    end

elseif platform.features.liquid then

    ffi.cdef[[
    typedef struct fftplan_s * fftplan;
    fftplan fft_create_plan(unsigned int _n, complex_float32_t *_x, complex_float32_t *_y, int _dir, int _flags);
    void fft_destroy_plan(fftplan _p);

    void fft_execute(fftplan _p);
    void fft_shift(complex_float32_t *_x, unsigned int _n);

    enum { LIQUID_FFT_FORWARD = +1, LIQUID_FFT_BACKWARD = -1 };
    ]]
    local libliquid = platform.libs.liquid

    function DFT:initialize()
        -- Create plan
        if self.data_type == types.ComplexFloat32 then
            self.plan = ffi.gc(libliquid.fft_create_plan(self.num_samples, self.input_samples.data, self.output_samples.data, ffi.C.LIQUID_FFT_FORWARD, 0), libliquid.fft_destroy_plan)
        else
            -- Create complex samples buffer for compute_real()
            self._complex_input_samples = types.ComplexFloat32.vector(self.num_samples)

            self.plan = ffi.gc(libliquid.fft_create_plan(self.num_samples, self._complex_input_samples.data, self.output_samples.data, ffi.C.LIQUID_FFT_FORWARD, 0), libliquid.fft_destroy_plan)
        end

        if self.plan == nil then
            error("Creating liquid fftplan object.")
        end
    end

    function DFT:compute_complex()
        -- Execute liquid fft plan
        libliquid.fft_execute(self.plan)
    end

    function DFT:compute_real()
        -- liquid-dsp doesn't provide a r2c DFT, so we copy real samples into a
        -- complex sample buffer and use the c2c DFT.

        -- Copy real samples to complex samples
        for i = 0, self.num_samples-1 do
            self._complex_input_samples.data[i].real = self.input_samples.data[i].value
        end

        -- Execute liquid fft plan
        libliquid.fft_execute(self.plan)
    end

elseif platform.features.volk then

    ffi.cdef[[
    void (*volk_32fc_s32fc_x2_rotator_32fc_a)(complex_float32_t* outVector, const complex_float32_t* inVector, const complex_float32_t phase_inc, complex_float32_t* phase, unsigned int num_points);
    void (*volk_32fc_x2_dot_prod_32fc_a)(complex_float32_t* result, const complex_float32_t* input, const complex_float32_t* taps, unsigned int num_points);
    void (*volk_32fc_32f_dot_prod_32fc_a)(complex_float32_t* result, const complex_float32_t* input, const float32_t* taps, unsigned int num_points);
    ]]
    local libvolk = platform.libs.volk

    function DFT:initialize()
        -- Generate complex exponentials
        self.exponentials = {}
        for k = 0, self.num_samples-1 do
            self.exponentials[k] = types.ComplexFloat32.vector(self.num_samples)
            local omega = (-2*math.pi*k)/self.num_samples
            for n = 0, self.num_samples-1 do
                self.exponentials[k].data[n] = types.ComplexFloat32(math.cos(omega*n), math.sin(omega*n))
            end
        end
    end

    function DFT:compute_complex()
        -- Compute DFT (dot product of each complex exponential with the input samples)
        for k = 0, self.num_samples-1 do
            libvolk.volk_32fc_x2_dot_prod_32fc_a(self.output_samples.data[k], self.input_samples.data, self.exponentials[k].data, self.num_samples)
        end
    end

    function DFT:compute_real()
        -- Compute DFT (dot product of each complex exponential with the input samples)
        for k = 0, self.num_samples/2 do
            libvolk.volk_32fc_32f_dot_prod_32fc_a(self.output_samples.data[k], self.exponentials[k].data, self.input_samples.data, self.num_samples)
        end

        -- Populate negative frequencies
        for k = math.floor(self.num_samples/2)+1, self.num_samples-1 do
            self.output_samples.data[k].real = self.output_samples.data[self.num_samples-k].real
            self.output_samples.data[k].imag = -self.output_samples.data[self.num_samples-k].imag
        end
    end

else

    function DFT:initialize()
        -- Generate complex exponentials
        self.exponentials = {}
        for k = 0, self.num_samples-1 do
            self.exponentials[k] = types.ComplexFloat32.vector(self.num_samples)
            local omega = (-2*math.pi*k)/self.num_samples
            for n = 0, self.num_samples-1 do
                self.exponentials[k].data[n] = types.ComplexFloat32(math.cos(omega*n), math.sin(omega*n))
            end
        end
    end

    function DFT:compute_complex()
        -- Compute DFT (dot product of each complex exponential with the input samples)
        ffi.fill(self.output_samples.data, self.output_samples.size)
        for k = 0, self.num_samples-1 do
            for n = 0, self.num_samples-1 do
                self.output_samples.data[k] = self.output_samples.data[k] + self.exponentials[k].data[n]*self.input_samples.data[n]
            end
        end
    end

    function DFT:compute_real()
        -- Zero DFT output samples
        ffi.fill(self.output_samples.data, self.output_samples.size)

        -- Compute DFT (dot product of each complex exponential with the input samples)
        for k = 0, self.num_samples/2 do
            for n = 0, self.num_samples-1 do
                self.output_samples.data[k] = self.output_samples.data[k] + self.exponentials[k].data[n]:scalar_mul(self.input_samples.data[n].value)
            end
        end

        -- Populate negative frequencies
        for k = math.floor(self.num_samples/2)+1, self.num_samples-1 do
            self.output_samples.data[k].real = self.output_samples.data[self.num_samples-k].real
            self.output_samples.data[k].imag = -self.output_samples.data[self.num_samples-k].imag
        end
    end

end

--------------------------------------------------------------------------------
-- IDFT
--------------------------------------------------------------------------------

---
-- Inverse Discrete Fourier Transform class.
--
-- @internal
-- @class IDFT
-- @tparam vector input_samples ComplexFloat32 vector of input DFT samples
-- @tparam vector output_samples ComplexFloat32 or Float32 vector of output samples
local IDFT = class.factory()

function IDFT.new(input_samples, output_samples)
    local self = setmetatable({}, IDFT)

    if input_samples.data_type ~= types.ComplexFloat32 then
        error("Unsupported input samples data type.")
    elseif output_samples.data_type ~= types.ComplexFloat32 and output_samples.data_type ~= types.Float32 then
        error("Unsupported ouptut samples data type.")
    elseif input_samples.length ~= output_samples.length then
        error("Input samples and output samples length mismatch.")
    elseif (input_samples.length % 2) ~= 0 then
        error("DFT length must be even.")
    end

    self.input_samples = input_samples
    self.output_samples = output_samples

    self.num_samples = self.input_samples.length
    self.data_type = self.output_samples.data_type

    -- Pick complex or real DFT
    if self.data_type == types.ComplexFloat32 then
        self.compute = self.compute_complex
    else
        self.compute = self.compute_real
    end

    -- Initialize the IDFT
    self:initialize()

    return self
end

---
-- Compute the inverse discrete fourier transform.
--
-- @internal
-- @function IDFT:compute

--------------------------------------------------------------------------------
-- IDFT implementations
--------------------------------------------------------------------------------

if platform.features.fftw3f then

    ffi.cdef[[
    typedef struct fftwf_plan_s *fftwf_plan;
    typedef float32_t fftwf_real;
    typedef complex_float32_t fftwf_complex;

    fftwf_plan fftwf_plan_dft_1d(int n, fftwf_complex *in, fftwf_complex *out, int sign, unsigned flags);
    fftwf_plan fftwf_plan_dft_c2r_1d(int n0, fftwf_complex *in, fftwf_real *out, unsigned flags);
    void fftwf_execute(const fftwf_plan plan);
    void fftwf_destroy_plan(fftwf_plan plan);
    ]]
    local libfftw3f = platform.libs.fftw3f

    function IDFT:initialize()
        -- Create plan
        if self.data_type == types.ComplexFloat32 then
            self.plan = ffi.gc(libfftw3f.fftwf_plan_dft_1d(self.num_samples, self.input_samples.data, self.output_samples.data, ffi.C.FFTW_BACKWARD, ffi.C.FFTW_ESTIMATE), libfftw3f.fftwf_destroy_plan)
        else
            self.plan = ffi.gc(libfftw3f.fftwf_plan_dft_c2r_1d(self.num_samples, self.input_samples.data, self.output_samples.data, ffi.C.FFTW_ESTIMATE), libfftw3f.fftwf_destroy_plan)
        end

        if self.plan == nil then
            error("Creating FFTW plan.")
        end
    end

    function IDFT:compute_complex()
        -- Execute FFTW plan
        libfftw3f.fftwf_execute(self.plan)

        -- Normalize inverse transform
        for i = 0, self.num_samples-1 do
            self.output_samples.data[i].real = self.output_samples.data[i].real*(1/self.num_samples)
            self.output_samples.data[i].imag = self.output_samples.data[i].imag*(1/self.num_samples)
        end
    end

    function IDFT:compute_real()
        -- Execute FFTW plan
        libfftw3f.fftwf_execute(self.plan)

        -- Normalize output
        for i = 0, self.num_samples-1 do
            self.output_samples.data[i].value = self.output_samples.data[i].value*(1/self.num_samples)
        end
    end

elseif platform.features.liquid then

    ffi.cdef[[
    typedef struct fftplan_s * fftplan;
    fftplan fft_create_plan(unsigned int _n, complex_float32_t *_x, complex_float32_t *_y, int _dir, int _flags);
    void fft_destroy_plan(fftplan _p);

    void fft_execute(fftplan _p);
    void fft_shift(complex_float32_t *_x, unsigned int _n);
    ]]
    local libliquid = platform.libs.liquid

    function IDFT:initialize()
        -- Create plan
        if self.data_type == types.ComplexFloat32 then
            self.plan = ffi.gc(libliquid.fft_create_plan(self.num_samples, self.input_samples.data, self.output_samples.data, ffi.C.LIQUID_FFT_BACKWARD, 0), libliquid.fft_destroy_plan)
        else
            -- Create complex samples buffer for compute_real()
            self._complex_output_samples = types.ComplexFloat32.vector(self.num_samples)

            self.plan = ffi.gc(libliquid.fft_create_plan(self.num_samples, self.input_samples.data, self._complex_output_samples.data, ffi.C.LIQUID_FFT_BACKWARD, 0), libliquid.fft_destroy_plan)
        end

        if self.plan == nil then
            error("Creating liquid fftplan object.")
        end
    end

    function IDFT:compute_complex()
        -- Execute liquid fft plan
        libliquid.fft_execute(self.plan)

        -- Normalize output
        for i = 0, self.num_samples-1 do
            self.output_samples.data[i].real = self.output_samples.data[i].real*(1/self.num_samples)
            self.output_samples.data[i].imag = self.output_samples.data[i].imag*(1/self.num_samples)
        end
    end

    function IDFT:compute_real()
        -- liquid-dsp doesn't provide a c2r IDFT, so we use the c2c IDFT and
        -- take the real part of the complex output samples to the real output
        -- samples.

        -- Execute liquid fft plan
        libliquid.fft_execute(self.plan)

        -- Normalize output, while taking real part of complex samples
        for i = 0, self.num_samples-1 do
            self.output_samples.data[i].value = self._complex_output_samples.data[i].real*(1/self.num_samples)
        end
    end

elseif platform.features.volk then

    ffi.cdef[[
    void (*volk_32fc_s32fc_x2_rotator_32fc_a)(complex_float32_t* outVector, const complex_float32_t* inVector, const complex_float32_t phase_inc, complex_float32_t* phase, unsigned int num_points);
    void (*volk_32fc_x2_dot_prod_32fc_a)(complex_float32_t* result, const complex_float32_t* input, const complex_float32_t* taps, unsigned int num_points);
    ]]
    local libvolk = platform.libs.volk

    function IDFT:initialize()
        -- Generate complex exponentials
        self.exponentials = {}
        for k = 0, self.num_samples-1 do
            self.exponentials[k] = types.ComplexFloat32.vector(self.num_samples)
            local omega = (2*math.pi*k)/self.num_samples
            for n = 0, self.num_samples-1 do
                self.exponentials[k].data[n] = types.ComplexFloat32(math.cos(omega*n), math.sin(omega*n))
            end
        end

        if self.data_type == types.Float32 then
            -- Create complex samples buffer for compute_real()
            self._complex_output_samples = types.ComplexFloat32.vector(self.num_samples)
        end
    end

    function IDFT:compute_complex()
        -- Compute IDFT (dot product of each complex exponential with the input samples)
        for k = 0, self.num_samples-1 do
            libvolk.volk_32fc_x2_dot_prod_32fc_a(self.output_samples.data[k], self.input_samples.data, self.exponentials[k].data, self.num_samples)
        end

        -- Normalize output
        for i = 0, self.num_samples-1 do
            self.output_samples.data[i].real = self.output_samples.data[i].real*(1/self.num_samples)
            self.output_samples.data[i].imag = self.output_samples.data[i].imag*(1/self.num_samples)
        end
    end

    function IDFT:compute_real()
        -- Compute IDFT (dot product of each complex exponential with the input samples)
        for k = 0, self.num_samples-1 do
            libvolk.volk_32fc_x2_dot_prod_32fc_a(self._complex_output_samples.data[k], self.input_samples.data, self.exponentials[k].data, self.num_samples)
        end

        -- Normalize output, while taking real part of complex samples
        for i = 0, self.num_samples-1 do
            self.output_samples.data[i].value = self._complex_output_samples.data[i].real*(1/self.num_samples)
        end
    end

else

    function IDFT:initialize()
        -- Generate complex exponentials
        self.exponentials = {}
        for k = 0, self.num_samples-1 do
            self.exponentials[k] = types.ComplexFloat32.vector(self.num_samples)
            local omega = (2*math.pi*k)/self.num_samples
            for n = 0, self.num_samples-1 do
                self.exponentials[k].data[n] = types.ComplexFloat32(math.cos(omega*n), math.sin(omega*n))
            end
        end

        if self.data_type == types.Float32 then
            -- Create complex samples buffer for compute_real()
            self._complex_output_samples = types.ComplexFloat32.vector(self.num_samples)
        end
    end

    function IDFT:compute_complex()
        -- Compute IDFT (dot product of each complex exponential with the input samples)
        ffi.fill(self.output_samples.data, self.output_samples.size)
        for k = 0, self.num_samples-1 do
            for n = 0, self.num_samples-1 do
                self.output_samples.data[k] = self.output_samples.data[k] + self.exponentials[k].data[n]*self.input_samples.data[n]
            end
        end

        -- Normalize output
        for i = 0, self.num_samples-1 do
            self.output_samples.data[i].real = self.output_samples.data[i].real*(1/self.num_samples)
            self.output_samples.data[i].imag = self.output_samples.data[i].imag*(1/self.num_samples)
        end
    end

    function IDFT:compute_real()
        -- Zero IDFT complex output samples
        ffi.fill(self._complex_output_samples.data, self._complex_output_samples.size)

        -- Compute IDFT (dot product of each complex exponential with the input samples)
        for k = 0, self.num_samples-1 do
            for n = 0, self.num_samples-1 do
                self._complex_output_samples.data[k] = self._complex_output_samples.data[k] + self.exponentials[k].data[n]*self.input_samples.data[n]
            end
        end

        -- Normalize output, while taking real part of complex samples
        for i = 0, self.num_samples-1 do
            self.output_samples.data[i].value = self._complex_output_samples.data[i].real*(1/self.num_samples)
        end
    end

end

--------------------------------------------------------------------------------
-- PSD
--------------------------------------------------------------------------------

---
-- Power Spectral Density class.
--
-- @internal
-- @class PSD
-- @tparam vector input_samples ComplexFloat32 or Float32 vector of input samples
-- @tparam vector output_samples Float32 vector of output power spectral density samples
-- @tparam[opt='hamming'] string window_type Window type
-- @tparam[opt=2] number sample_rate Sample rate in Hz
-- @tparam[opt=true] bool logarithmic Scale power logarithmically, with `10*log10()`
local PSD = class.factory()

function PSD.new(input_samples, output_samples, window_type, sample_rate, logarithmic)
    local self = setmetatable({}, PSD)

    if input_samples.data_type ~= types.ComplexFloat32 and input_samples.data_type ~= types.Float32 then
        error("Unsupported input samples data type.")
    elseif output_samples.data_type ~= types.Float32 then
        error("Unsupported output samples data type.")
    elseif input_samples.length ~= output_samples.length then
        error("Input samples and output samples length mismatch.")
    elseif (input_samples.length % 2) ~= 0 then
        error("PSD length must be even.")
    end

    self.input_samples = input_samples
    self.output_samples = output_samples
    self.window_type = window_type or "hamming"
    self.sample_rate = sample_rate or 2
    self.logarithmic = (logarithmic == nil) and true or logarithmic

    self.num_samples = self.input_samples.length
    self.data_type = self.input_samples.data_type

    -- Generate window
    self.window = types.Float32.vector_from_array(window_utils.window(self.num_samples, self.window_type, true))

    -- Calculate window energy
    self.window_energy = 0
    for i = 0, self.num_samples-1 do
        self.window_energy = self.window_energy + self.window.data[i].value*self.window.data[i].value
    end

    -- Create sample buffers and DFT context
    self.windowed_samples = input_samples.data_type.vector(self.num_samples)
    self.dft_samples = types.ComplexFloat32.vector(self.num_samples)
    self.dft = DFT(self.windowed_samples, self.dft_samples)

    return self
end

---
-- Compute the power spectral density.
--
-- @internal
-- @function PSD:compute

--------------------------------------------------------------------------------
-- PSD implementations
--------------------------------------------------------------------------------

if platform.features.volk then

    ffi.cdef[[
    void (*volk_32fc_32f_multiply_32fc_a)(complex_float32_t* cVector, const complex_float32_t* aVector, const float32_t* bVector, unsigned int num_points);
    void (*volk_32f_x2_multiply_32f_a)(float32_t* cVector, const float32_t* aVector, const float32_t* bVector, unsigned int num_points);

    void (*volk_32fc_s32f_x2_power_spectral_density_32f_a)(float32_t* logPowerOutput, const complex_float32_t* complexFFTInput, const float normalizationFactor, const float rbw, unsigned int num_points);
    void (*volk_32fc_magnitude_squared_32f_a)(float32_t* magnitudeVector, const complex_float32_t* complexVector, unsigned int num_points);
    void (*volk_32f_s32f_normalize_a)(float32_t* vecBuffer, const float scalar, unsigned int num_points);
    ]]
    local libvolk = platform.libs.volk

    function PSD:compute()
        -- Window samples
        if self.data_type == types.ComplexFloat32 then
            libvolk.volk_32fc_32f_multiply_32fc_a(self.windowed_samples.data, self.input_samples.data, self.window.data, self.num_samples)
        else
            libvolk.volk_32f_x2_multiply_32f_a(self.windowed_samples.data, self.input_samples.data, self.window.data, self.num_samples)
        end

        -- Compute DFT
        self.dft:compute()

        -- Scaling factor
        local scale = self.sample_rate * self.window_energy

        if self.logarithmic then
            -- Compute 10*log10((X_k)^2 / Scale)
            libvolk.volk_32fc_s32f_x2_power_spectral_density_32f_a(self.output_samples.data, self.dft_samples.data, 1.0, scale, self.num_samples)
        else
            -- Compute (X_k)^2 / Scale
            libvolk.volk_32fc_magnitude_squared_32f_a(self.output_samples.data, self.dft_samples.data, self.num_samples)
            libvolk.volk_32f_s32f_normalize_a(self.output_samples.data, scale, self.num_samples)
        end
    end

else

    function PSD:compute()
        -- Window samples
        if self.data_type == types.ComplexFloat32 then
            for i = 0, self.num_samples-1 do
                self.windowed_samples.data[i] = self.input_samples.data[i]:scalar_mul(self.window.data[i].value)
            end
        else
            for i = 0, self.num_samples-1 do
                self.windowed_samples.data[i].value = self.input_samples.data[i].value*self.window.data[i].value
            end
        end

        -- Compute DFT
        self.dft:compute()

        -- Scaling factor
        local scale = self.sample_rate * self.window_energy

        if self.logarithmic then
            -- Compute 10*log10((X_k)^2 / Scale)
            for i = 0, self.num_samples-1 do
                self.output_samples.data[i].value = 10*math.log10(self.dft_samples.data[i]:abs_squared() / scale)
            end
        else
            -- Compute (X_k)^2 / Scale
            for i = 0, self.num_samples-1 do
                self.output_samples.data[i].value = self.dft_samples.data[i]:abs_squared() / scale
            end
        end
    end

end

--------------------------------------------------------------------------------
-- fftshift()
--------------------------------------------------------------------------------

---
-- Shift frequency components into negative, zero, positive frequency order.
--
-- @internal
-- @function fftshift
-- @tparam vector samples ComplexFloat32 or Float32 vector of samples
local function fftshift(samples)
    local offset = samples.length/2

    if samples.data_type == types.ComplexFloat32 then
        for k = 0, (samples.length/2)-1 do
            samples.data[k].real, samples.data[k+offset].real = samples.data[k+offset].real, samples.data[k].real
            samples.data[k].imag, samples.data[k+offset].imag = samples.data[k+offset].imag, samples.data[k].imag
        end
    else
        for k = 0, (samples.length/2)-1 do
            samples.data[k].value, samples.data[k+offset].value = samples.data[k+offset].value, samples.data[k].value
        end
    end
end

return {DFT = DFT, IDFT = IDFT, PSD = PSD, fftshift = fftshift}
