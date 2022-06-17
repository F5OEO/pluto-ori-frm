
-- LamaBleu - 09/2019
-- Create IQ stream from WAV input file (48000Hz)
-- SR Pluto : 576000


local radio = require('radio')



    io.stderr:write("Usage: " .. arg[0] .. "<input file>  \n")
    io.stderr:write("Input file /tmp/send.png.wav, output IQ to stdout \n")


if #arg < 1 then
    arg[1]='/tmp/send.png.wav'

end

local input_file = arg[1]


io.stderr:write(input_file)

-- Blocks
local source = radio.WAVFileSource(input_file, 1)
local af_filter = radio.LowpassFilterBlock(128, 3400)
local hilbert = radio.HilbertTransformBlock(129)
local sb_filter = radio.ComplexBandpassFilterBlock(129, {0, 3400})
-- local sink = radio.IQFileSink('/tmp/send.png.iq', 'f32le')
local filter2 = radio.ComplexBandpassFilterBlock(130, {0, 5000})
local interpolator = radio.InterpolatorBlock(12)
-- local srciq = radio.IQFileSource('/tmp/send.png.iq', 'f32le', 48e3)
local sinkiio = radio.IQFileSink(1, 's16le')


-- Connections
io.stderr:write("Create IQ 576kS from WAV, wait ...")
-- Connections
local wav2iq = radio.CompositeBlock()
      wav2iq:connect(source, af_filter, hilbert, sb_filter, interpolator, filter2, sinkiio)


wav2iq:run()


