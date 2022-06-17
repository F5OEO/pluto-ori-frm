---
-- Pipe I/O handling.
--
-- @module radio.core.pipe

local ffi = require('ffi')
local math = require('math')

local class = require('radio.core.class')
local platform = require('radio.core.platform')
local util = require('radio.core.util')

---
-- Pipe. This class implements the serialization/deserialization of sample
-- vectors between blocks.
--
-- @internal
-- @class
-- @tparam OutputPort output Pipe output port
-- @tparam InputPort input Pipe input port
local Pipe = class.factory()

function Pipe.new(output, input)
    local self = setmetatable({}, Pipe)
    self.output = output
    self.input = input
    return self
end

---
-- Get sample rate of pipe.
--
-- @internal
-- @function Pipe:get_rate
-- @treturn number Sample rate
function Pipe:get_rate()
    assert(self.output, "Sample rate unavailable for anonymous pipes")
    return self.output.owner:get_rate()
end

ffi.cdef[[
    int socketpair(int domain, int type, int protocol, int socket_vector[2]);
]]

---
-- Initialize the pipe.
--
-- @internal
-- @function Pipe:initialize
-- @tparam[opt] data_type data_type Data type
-- @tparam[opt] int read_fd Read file descriptor
-- @tparam[opt] int write_fd Write file descriptor
function Pipe:initialize(data_type, read_fd, write_fd)
    self.data_type = data_type or self.output.data_type

    assert(self.data_type, "Unknown data type")

    if not read_fd and not write_fd then
        -- Create UNIX socket pair
        local socket_fds = ffi.new("int[2]")
        if ffi.C.socketpair(ffi.C.AF_UNIX, ffi.C.SOCK_STREAM, 0, socket_fds) ~= 0 then
            error("socketpair(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
        self._rfd = socket_fds[0]
        self._wfd = socket_fds[1]
    else
        self._rfd = read_fd or nil
        self._wfd = write_fd or nil
    end

    -- Read buffer
    if self._rfd then
        self._rbuf_capacity = 1048576
        self._rbuf_anchor = platform.alloc(self._rbuf_capacity)
        self._rbuf = ffi.cast("char *", self._rbuf_anchor)
        self._rbuf_size = 0
        self._rbuf_offset = 0
        self._rbuf_count = 0
    end

    -- Write buffer
    if self._wfd then
        self._wbuf_anchor = nil
        self._wbuf = nil
        self._wbuf_size = 0
        self._wbuf_offset = 0
    end
end

--------------------------------------------------------------------------------
-- Read methods
--------------------------------------------------------------------------------

---
-- Update the Pipe's internal read buffer.
--
-- @internal
-- @function Pipe:_read_buffer_update
-- @treturn int|nil Number of bytes read or nil on EOF
function Pipe:_read_buffer_update()
    -- Shift unread samples down to beginning of buffer
    local unread_length = self._rbuf_size - self._rbuf_offset
    if unread_length > 0 then
        ffi.C.memmove(self._rbuf, self._rbuf + self._rbuf_offset, unread_length)
    end

    -- Read new samples in
    local bytes_read = tonumber(ffi.C.read(self._rfd, self._rbuf + unread_length, self._rbuf_capacity - unread_length))
    if bytes_read < 0 then
        error("read(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    elseif unread_length == 0 and bytes_read == 0 then
        return nil
    end

    -- Update size and reset unread offset
    self._rbuf_size = unread_length + bytes_read
    self._rbuf_offset = 0

    -- Update element count
    self._rbuf_count = self.data_type.deserialize_count(self._rbuf + self._rbuf_offset, self._rbuf_size - self._rbuf_offset)

    return bytes_read
end

---
-- Get the Pipe's internal read buffer's element count.
--
-- @internal
-- @function Pipe:_read_buffer_count
-- @treturn int Count
function Pipe:_read_buffer_count()
    return self._rbuf_count
end

---
-- Test if the Pipe's internal read buffer is full.
--
-- @internal
-- @function Pipe:_read_buffer_full
-- @treturn bool Full
function Pipe:_read_buffer_full()
    -- Return full status of read buffer
    return (self._rbuf_size - self._rbuf_offset) == self._rbuf_capacity
end

---
-- Deserialize elements from the Pipe's internal read buffer into a vector.
--
-- @internal
-- @function Pipe:_read_buffer_deserialize
-- @tparam int num Number of elements to deserialize
-- @treturn Vector Vector
function Pipe:_read_buffer_deserialize(num)
    -- Shift samples down to beginning of buffer
    if self._rbuf_offset > 0 then
        ffi.C.memmove(self._rbuf, self._rbuf + self._rbuf_offset, self._rbuf_size - self._rbuf_offset)
        self._rbuf_size = self._rbuf_size - self._rbuf_offset
        self._rbuf_offset = 0
    end

    -- Deserialize a vector from the read buffer
    local vec, size = self.data_type.deserialize_partial(self._rbuf, num)

    -- Update read offset
    self._rbuf_offset = self._rbuf_offset + size
    self._rbuf_count = self._rbuf_count - num

    return vec
end

---
-- Read a sample vector from the Pipe.
--
-- @internal
-- @function Pipe:read
-- @tparam[opt=nil] int count Number of elements to read
-- @treturn Vector|nil Sample vector or nil on EOF
function Pipe:read(count)
    -- Check if count is already available without updating read buffer
    if count and self:_read_buffer_count() >= count then
        return self:_read_buffer_deserialize(count)
    end

    -- Update our read buffer
    if self:_read_buffer_update() == nil then
        -- Return nil on EOF
        return nil
    end

    -- Get available item count
    local available = self:_read_buffer_count()

    return self:_read_buffer_deserialize(count and math.min(available, count) or available)
end

--------------------------------------------------------------------------------
-- Write methods
--------------------------------------------------------------------------------

---
-- Update the Pipe's internal write buffer.
--
-- @internal
-- @function Pipe:_write_buffer_update
-- @treturn int|nil Number of bytes written or nil on EOF
function Pipe:_write_buffer_update()
    local bytes_written = tonumber(ffi.C.write(self._wfd, self._wbuf + self._wbuf_offset, self._wbuf_size - self._wbuf_offset))
    if bytes_written < 0 then
        local errno = ffi.errno()
        if errno == ffi.C.EPIPE or errno == ffi.C.ECONNRESET then
            return nil
        end
        error("write(): " .. ffi.string(ffi.C.strerror(errno)))
    end

    self._wbuf_offset = self._wbuf_offset + bytes_written

    return bytes_written
end

---
-- Test if the Pipe's internal write buffer is empty.
--
-- @internal
-- @function Pipe:_write_buffer_full
-- @treturn bool Empty
function Pipe:_write_buffer_empty()
    -- Return empty status of write buffer
    return self._wbuf_offset == self._wbuf_size
end

---
-- Serialize elements from a vector to the Pipe's internal write buffer.
--
-- @internal
-- @function Pipe:_write_buffer_serialize
-- @tparam Vector vec Sample vector
function Pipe:_write_buffer_serialize(vec)
    -- Serialize to buffer
    self._wbuf_anchor, self._wbuf_size = self.data_type.serialize(vec)
    self._wbuf = ffi.cast("char *", self._wbuf_anchor)
    self._wbuf_offset = 0
end

---
-- Write a sample vector to the Pipe.
--
-- @internal
-- @function Pipe:write
-- @tparam Vector vec Sample vector
-- @treturn bool Success
function Pipe:write(vec)
    self:_write_buffer_serialize(vec)

    while not self:_write_buffer_empty() do
        if self:_write_buffer_update() == nil then
            return false
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Misc methods
--------------------------------------------------------------------------------

---
-- Close the input end of the pipe.
--
-- @internal
-- @function Pipe:close_input
function Pipe:close_input()
    if self._rfd then
        if ffi.C.close(self._rfd) ~= 0 then
            error("close(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
        self._rfd = nil
    end
end

---
-- Close the output end of the pipe.
--
-- @internal
-- @function Pipe:close_output
function Pipe:close_output()
    if self._wfd then
        if ffi.C.close(self._wfd) ~= 0 then
            error("close(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
        self._wfd = nil
    end
end

---
-- Get the file descriptor of the input end of the Pipe.
--
-- @internal
-- @function Pipe:fileno_input
-- @treturn int File descriptor
function Pipe:fileno_input()
    return self._rfd
end

---
-- Get the file descriptor of the output end of the Pipe.
--
-- @internal
-- @function Pipe:fileno_output
-- @treturn int File descriptor
function Pipe:fileno_output()
    return self._wfd
end

--------------------------------------------------------------------------------
-- ControlSocket
--------------------------------------------------------------------------------

---
-- ControlSocket. This class implements an out-of-band, asynchronous control
-- interface to blocks.
--
-- @internal
-- @class
-- @tparam Block block Block
local ControlSocket = class.factory()

function ControlSocket.new(block)
    local self = setmetatable({}, ControlSocket)
    self.block = block
    return self
end

---
-- Initialize the pipe.
--
-- @internal
-- @function ControlSocket:initialize
function ControlSocket:initialize()
    -- Create UNIX socket pair
    local socket_fds = ffi.new("int[2]")
    if ffi.C.socketpair(ffi.C.AF_UNIX, ffi.C.SOCK_STREAM, 0, socket_fds) ~= 0 then
        error("socketpair(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end
    self._host_fd = socket_fds[0]
    self._block_fd = socket_fds[1]
end

---
-- Close the block side of the control socket.
--
-- @internal
-- @function ControlSocket:close_block
function ControlSocket:close_block()
    if self._block_fd then
        if ffi.C.close(self._block_fd) ~= 0 then
            error("close(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
        self._block_fd = nil
    end
end

---
-- Close the host side of the control socket.
--
-- @internal
-- @function ControlSocket:close_host
function ControlSocket:close_host()
    if self._host_fd then
        if ffi.C.close(self._host_fd) ~= 0 then
            error("close(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
        self._host_fd = nil
    end
end

---
-- Get the file descriptor of the block side of the ControlSocket.
--
-- @internal
-- @function ControlSocket:fileno_block
-- @treturn int File descriptor
function ControlSocket:fileno_block()
    return self._block_fd
end

---
-- Get the file descriptor of the host side of the ControlSocket.
--
-- @internal
-- @function ControlSocket:fileno_host
-- @treturn int File descriptor
function ControlSocket:fileno_host()
    return self._host_fd
end

--------------------------------------------------------------------------------
-- PipeMux
--------------------------------------------------------------------------------

local POLL_READ_EVENTS = bit.bor(ffi.C.POLLIN, ffi.C.POLLHUP)
local POLL_WRITE_EVENTS = bit.bor(ffi.C.POLLOUT, ffi.C.POLLHUP)
local POLL_EOF_EVENTS = ffi.C.POLLHUP

---
-- Helper class to manage reading and writing to and from a group of pipes
-- efficiently.
--
-- @internal
-- @class
-- @tparam array input_pipes Input pipes
-- @tparam array output_pipes Output pipes
-- @tparam ControlSocket control_socket Control socket
local PipeMux = class.factory()

function PipeMux.new(input_pipes, output_pipes, control_socket)
    local self = setmetatable({}, PipeMux)

    -- Save input pipes
    self.input_pipes = input_pipes

    -- Save output pipes
    self.output_pipes = output_pipes
    self.output_pipes_flat = util.array_flatten(output_pipes, 1)

    -- Save control socket
    self.control_socket = control_socket

    -- Initialize input pollfds
    self.input_pollfds = ffi.new("struct pollfd[?]", #self.input_pipes + 1)
    self.input_pollfds[0].fd = self.control_socket and self.control_socket:fileno_block() or -1
    self.input_pollfds[0].events = POLL_EOF_EVENTS
    for i=1, #self.input_pipes do
        self.input_pollfds[i].fd = input_pipes[i]:fileno_input()
        self.input_pollfds[i].events = POLL_READ_EVENTS
    end

    -- Differentiate read() method
    if #self.input_pipes == 0 and #self.output_pipes == 0 and control_socket then
        self.read = self._read_control
    elseif #self.input_pipes == 0 then
        self.read = self._read_none
    elseif #self.input_pipes == 1 then
        self.read = self._read_single
    elseif #self.input_pipes > 1 then
        self.read = self._read_multiple
    end

    -- Initialize output pollfds
    self.output_pollfds = ffi.new("struct pollfd[?]", #self.output_pipes_flat + 1)
    self.output_pollfds[0].fd = self.control_socket and self.control_socket:fileno_block() or -1
    self.output_pollfds[0].events = POLL_EOF_EVENTS
    for i=1, #self.output_pipes_flat do
        self.output_pollfds[i].fd = self.output_pipes_flat[i]:fileno_output()
        self.output_pollfds[i].events = POLL_WRITE_EVENTS
    end

    -- Differentiate write() method
    if #self.output_pipes_flat == 0 then
        self.write = self._write_none
    elseif #self.output_pipes_flat == 1 then
        self.write = self._write_single
    elseif #self.output_pipes_flat > 1 then
        self.write = self._write_multiple
    end

    return self
end

function PipeMux:_read_none(count)
    return {}, false, false
end

function PipeMux:_read_control(count)
    local num_elems

    while true do
        -- Poll (blocking)
        local ret = ffi.C.poll(self.input_pollfds, 1, -1)
        if ret < 0 then
            error("poll(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end

        -- Check control socket
        if self.input_pollfds[0].revents ~= 0 then
            -- Shutdown encountered
            return {}, false, true
        end
    end

    return {}, false, false
end

function PipeMux:_read_single(count)
    local num_elems

    -- Check if count is already available without updating read buffer
    if count and self.input_pipes[1]:_read_buffer_count() >= count then
        -- Read input vector
        return {self.input_pipes[1]:_read_buffer_deserialize(count)}, false, false
    end

    while true do
        -- Poll (blocking)
        local ret = ffi.C.poll(self.input_pollfds, 2, -1)
        if ret < 0 then
            error("poll(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end

        -- Check control socket
        if self.input_pollfds[0].revents ~= 0 then
            -- Shutdown encountered
            return {}, false, true
        end

        -- Update pipe internal read buffer
        if self.input_pipes[1]:_read_buffer_update() == nil then
            -- EOF encountered
            return {}, true, false
        end

        -- Check available item count
        local available = self.input_pipes[1]:_read_buffer_count()
        if (not count and available > 0) or (count and available >= count) then
            num_elems = count or available
            break
        end
    end

    -- Read input vector
    return {self.input_pipes[1]:_read_buffer_deserialize(num_elems)}, false, false
end

function PipeMux:_read_multiple(count)
    local num_elems

    assert(not count, "Count currently unsupported for reads from multiple pipes.")

    while true do
        -- Update pollfd structures
        for i=1, #self.input_pipes do
            self.input_pollfds[i].events = not self.input_pipes[i]:_read_buffer_full() and POLL_READ_EVENTS or POLL_EOF_EVENTS
        end

        -- Poll (blocking)
        local ret = ffi.C.poll(self.input_pollfds, #self.input_pipes + 1, -1)
        if ret < 0 then
            error("poll(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end

        -- Initialize available item count to maximum
        num_elems = math.huge

        -- Check control socket
        if self.input_pollfds[0].revents ~= 0 then
            -- Shutdown encountered
            return {}, false, true
        end

        -- Check each input pipe
        for i=1, #self.input_pipes do
            if self.input_pollfds[i].revents ~= 0 then
                -- Update pipe internal read buffer
                if self.input_pipes[i]:_read_buffer_update() == nil then
                    -- EOF encountered
                    return {}, true, false
                end
            end

             -- Update available item count
            local available = self.input_pipes[i]:_read_buffer_count()
            num_elems = (available < num_elems) and available or num_elems
        end

        -- If we have a non-zero, non-inf available item count
        if num_elems > 0 and num_elems < math.huge then
            break
        end
    end

    -- Read maxmium available item count from input vectors
    local data_in = {}
    for i=1, #self.input_pipes do
        data_in[i] = self.input_pipes[i]:_read_buffer_deserialize(num_elems)
    end

    return data_in, false, false
end

function PipeMux:_write_none(vecs)
    return false, nil, false
end

function PipeMux:_write_single(vecs)
    -- Serialize output vectors to pipe write buffers
    local eof, eof_pipe = false, nil
    if not self.output_pipes_flat[1]:write(vecs[1]) then
        eof, eof_pipe = true, self.output_pipes_flat[1]
    end

    -- Poll (blocking)
    local ret = ffi.C.poll(self.output_pollfds, 1, 0)
    if ret < 0 then
        error("poll(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end

    -- Check control socket
    if self.output_pollfds[0].revents ~= 0 then
        -- Shutdown encountered
        return eof, eof_pipe, true
    end

    return eof, eof_pipe, false
end

function PipeMux:_write_multiple(vecs)
    -- Serialize output vectors to pipe write buffers
    local eof, eof_pipe = false, nil
    for i=1, #self.output_pipes do
        for j=1, #self.output_pipes[i] do
            if not self.output_pipes[i][j]:write(vecs[i]) then
                eof, eof_pipe = true, self.output_pipes[i][j]
                break
            end
        end
    end

    -- Poll (blocking)
    local ret = ffi.C.poll(self.output_pollfds, 1, 0)
    if ret < 0 then
        error("poll(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end

    -- Check control socket
    if self.output_pollfds[0].revents ~= 0 then
        -- Shutdown encountered
        return eof, eof_pipe, true
    end

    return eof, eof_pipe, false
end

---
-- Read input pipes into an array of sample vectors.
--
-- @internal
-- @function PipeMux:read
-- @tparam[opt=nil] int count Number of elements to read
-- @treturn array Array of sample vectors
-- @treturn bool EOF encountered
-- @treturn bool Shutdown encountered
function PipeMux:read(count)
    -- Differentiated at runtime to _read_single() or _read_multiple()
end

---
-- Write an array of sample vectors to output pipes.
--
-- @internal
-- @function PipeMux:write
-- @tparam array vecs Array of sample vectors
-- @treturn bool EOF encountered
-- @treturn Pipe|nil Pipe that caused EOF
-- @treturn bool Shutdown encountered
function PipeMux:write(vecs)
    -- Differentiated at runtime to _write_single() or _write_multiple()
end

-- Exported module
return {Pipe = Pipe, ControlSocket = ControlSocket, PipeMux = PipeMux}
