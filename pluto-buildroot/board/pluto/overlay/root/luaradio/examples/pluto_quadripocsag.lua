local radio = require('radio')
local frequency = 466.122e6
local tune_offset = 0
local baudrate = 1200

-- Blocks

-- local source = radio.IQFileSource(io.stdin, 's16le', 1000e3)
-- local source = radio.RtlSdrSource(frequency + tune_offset, 240000)
local source = radio.SoapySDRSource("driver=plutosdr",frequency + tune_offset, 800000, {gain = 30})

local tuner = radio.TunerBlock(50e3, 12e3, 20)
local tuner2 = radio.TunerBlock(75e3, 12e3, 20)
local tuner3 = radio.TunerBlock(-50e3, 12e3, 20)
local tuner4 = radio.TunerBlock(-82e3, 12e3, 20)

local add = radio.AddBlock()
local add2 = radio.AddBlock()
local add3 = radio.AddBlock()
local space_filter = radio.ComplexBandpassFilterBlock(129, {3500, 5500})
local space_magnitude = radio.ComplexMagnitudeBlock()
local mark_filter = radio.ComplexBandpassFilterBlock(129, {-5500, -3500})
local mark_magnitude = radio.ComplexMagnitudeBlock()
local subtractor = radio.SubtractBlock()
local data_filter = radio.LowpassFilterBlock(129, baudrate)
local clock_recoverer = radio.ZeroCrossingClockRecoveryBlock(baudrate)
local sampler = radio.SamplerBlock()
local bit_slicer = radio.SlicerBlock()
local framer = radio.POCSAGFramerBlock()
local decoder = radio.POCSAGDecoderBlock()
local sink = radio.JSONSink()
-- local sink = radio.PrintSink(io.stdout,{"POCSAG", true})

-- Plotting sinks
 local plot1 = radio.GnuplotSpectrumSink(1024, 'POCSAG channel 1', {yrange = {-140, -50}})
 local plot2 = radio.GnuplotSpectrumSink(4096, 'IQ - 250kSps',{yrange = {-110, -50}})
 local plot3 = radio.GnuplotPlotSink(2048, 'Demodulated Bitstream')
 local plot4 = radio.GnuplotSpectrumSink(1024, 'POCSAG channel 2', {yrange = {-140, -50}})
 local plot5 = radio.GnuplotSpectrumSink(1024, 'POCSAG channel 3', {yrange = {-140, -50}})
 local plot6 = radio.GnuplotSpectrumSink(1024, 'POCSAG channel 4', {yrange = {-140, -50}})

-- Connections

local top = radio.CompositeBlock()
top:connect(source, tuner)
top:connect(source, tuner2)
top:connect(source, tuner3)
top:connect(source, tuner4)
top:connect(tuner, 'out', add2, 'in1')
top:connect(tuner2, 'out', add2, 'in2')
top:connect(tuner3, 'out', add3, 'in1')
top:connect(tuner4, 'out', add3, 'in2')
top:connect(add2, 'out', add, 'in1')
top:connect(add3, 'out', add, 'in2')
top:connect(add3, space_filter, space_magnitude)
top:connect(add3, mark_filter, mark_magnitude)
-- top:connect(add, space_filter, space_magnitude)
-- top:connect(add, mark_filter, mark_magnitude)
top:connect(mark_magnitude, 'out', subtractor, 'in1')
top:connect(space_magnitude, 'out', subtractor, 'in2')
top:connect(subtractor, data_filter, clock_recoverer)
top:connect(data_filter, 'out', sampler, 'data')
top:connect(clock_recoverer, 'out', sampler, 'clock')
top:connect(sampler, bit_slicer, framer, decoder, sink)

if os.getenv('DISPLAY') then
     top:connect(source, plot2)
     top:connect(tuner, plot1)
     top:connect(tuner2, plot4)
    top:connect(data_filter, plot3)
     top:connect(tuner3, plot5)
     top:connect(tuner4, plot6)
end

top:run()

