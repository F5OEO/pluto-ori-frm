local radio = require('radio')


    io.stderr:write("Usage: " .. arg[0] .. " \n")




-- Blocks
local sb_filter = radio.ComplexBandpassFilterBlock(129, {0, 5000})
local interpolator = radio.InterpolatorBlock(12)
local srciq = radio.IQFileSource('/tmp/send.png.iq', 'f32le', 48e3)
local sinkiio = radio.IQFileSink(1, 's16le')
-- Connections
local plutoiq =  radio.CompositeBlock()
	plutoiq:connect(srciq, interpolator, sb_filter, sinkiio)

io.stderr:write("Create pluto IQ, wait ...")
plutoiq:run()
