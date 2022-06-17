local radio = require('radio')

local frequency = tonumber(arg[1])
local tune_offset = 0e3
local baudrate = 1200

-- Blocks
-- local source = radio.IQFileSource('/root/luaradio/iqfifo','s16le',125000)
local source = radio.IQFileSource('/root/iqfifo','s16le',1000000)
local tuner = radio.TunerBlock(tune_offset, 12e3, 80)
local space_filter = radio.ComplexBandpassFilterBlock(129, {3500, 5500})
local space_magnitude = radio.ComplexMagnitudeBlock()
local mark_filter = radio.ComplexBandpassFilterBlock(129, {-5500, -3500})
local mark_magnitude = radio.ComplexMagnitudeBlock()
local subtractor = radio.SubtractBlock()
local data_filter = radio.LowpassFilterBlock(128, baudrate)
local clock_recoverer = radio.ZeroCrossingClockRecoveryBlock(baudrate)
local sampler = radio.SamplerBlock()
local bit_slicer = radio.SlicerBlock()
local framer = radio.POCSAGFramerBlock()
local decoder = radio.POCSAGDecoderBlock()
local sink = radio.JSONSink()


-- Connections
local top = radio.CompositeBlock()
top:connect(source, tuner)
top:connect(tuner, space_filter, space_magnitude)
top:connect(tuner, mark_filter, mark_magnitude)
top:connect(mark_magnitude, 'out', subtractor, 'in1')
top:connect(space_magnitude, 'out', subtractor, 'in2')
top:connect(subtractor, data_filter, clock_recoverer)
top:connect(data_filter, 'out', sampler, 'data')
top:connect(clock_recoverer, 'out', sampler, 'clock')
top:connect(sampler, bit_slicer, framer, decoder, sink)

top:run()
