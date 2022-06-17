---
-- Hierarchical and top-level block composition.
--
-- @module radio.core.composite

local ffi = require('ffi')
local string = require('string')
local io = require('io')

local class = require('radio.core.class')
local block = require('radio.core.block')
local pipe = require('radio.core.pipe')
local util = require('radio.core.util')
local platform = require('radio.core.platform')
local debug = require('radio.core.debug')

---
-- Create a block to hold a flow graph composition, for either top-level or
-- hierarchical purposes. Top-level blocks may be run with the `run()` method.
--
-- @class CompositeBlock
local CompositeBlock = block.factory("CompositeBlock")

function CompositeBlock:instantiate()
    self._running = false
    self._connections = {}
    self._blocks = {}
    self._evaluation_order = nil
end

-- Overridden implementation of Block's initialize().
function CompositeBlock:initialize()
    if not self._evaluation_order then
        self._evaluation_order = build_evaluation_order(build_dependency_graph(self._connections))
    end

    for _, block in ipairs(self._evaluation_order) do
        block:initialize()
    end
end

-- Connection logic

-- Overridden implementation of Block's add_type_signature().
function CompositeBlock:add_type_signature(inputs, outputs)
    block.Block.add_type_signature(self, inputs, outputs)

    -- Replace InputPort's with AliasedInputPort's
    for i = 1, #self.inputs do
        if class.isinstanceof(self.inputs[i], block.InputPort) then
            self.inputs[i] = block.AliasedInputPort(self, self.inputs[i].name)
        end
    end

    -- Replace OutputPort's with AliasedOutputPort's
    for i = 1, #self.outputs do
        if class.isinstanceof(self.outputs[i], block.OutputPort) then
            self.outputs[i] = block.AliasedOutputPort(self, self.outputs[i].name)
        end
    end
end

---
-- Connect blocks.
--
-- This method can be used in three ways:
--
-- **Linear block connections.** Connect the first output to the first input of
-- each adjacent block. This usage is convenient for connecting blocks that
-- only have one input port and output port (which is most blocks).
--
-- ``` lua
-- top:connect(b1, b2, b3)
-- ```
--
-- **Explicit block connections.** Connect a particular output of the first
-- block to a particular input of the second block. The output and input ports
-- are specified by name. This invocation is used to connect a block to another
-- block with multiple input ports.
--
-- ``` lua
-- top:connect(b1, 'out', b2, 'in2')
-- ```
--
-- **Alias port connections.** Alias a composite block's input or output port
-- to a concrete block's input or output port. This invocation is used for
-- connecting the boundary inputs and outputs of a hierarchical block.
--
-- ``` lua
-- function MyHierarchicalBlock:instantiate()
--     local b1, b2, b3 = ...
--
--     ...
--
--     self:connect(b1, b2, b3)
--
--     self:connect(self, 'in', b1, 'in')
--     self:connect(self, 'out', b3, 'out')
-- end
-- ```
--
-- @function CompositeBlock:connect
-- @param ... Blocks [and ports] to connect
-- @treturn CompositeBlock self
-- @raise Output port of block not found error.
-- @raise Input port of block not found error.
-- @raise Input port of block already connected error.
-- @raise Unexpected number of output ports in block error.
-- @raise Unexpected number of input ports in block error.
function CompositeBlock:connect(...)
    if util.array_all({...}, function (b) return class.isinstanceof(b, block.Block) end) then
        local blocks = {...}
        local first, second = blocks[1], nil

        for i = 2, #blocks do
            local second = blocks[i]
            assert(#first.outputs == 1, string.format("Unexpected number of output ports in block %d \"%s\": found %d, expected 1.", i-1, first.name, #first.outputs))
            assert(#second.inputs == 1, string.format("Unexpected number of input ports in block %d \"%s\": found %d, expected 1.", i, second.name, #second.inputs))
            self:_connect_by_name(first, first.outputs[1].name, second, second.inputs[1].name)
            first = blocks[i]
        end
    else
        self:_connect_by_name(...)
    end

    return self
end

function CompositeBlock:_connect_by_name(src, src_port_name, dst, dst_port_name)
    -- Look up port objects
    local src_port = util.array_search(src.outputs, function (p) return p.name == src_port_name end) or
                        util.array_search(src.inputs, function (p) return p.name == src_port_name end)
    local dst_port = util.array_search(dst.outputs, function (p) return p.name == dst_port_name end) or
                        util.array_search(dst.inputs, function (p) return p.name == dst_port_name end)

    assert(src_port, string.format("Output port \"%s\" of block \"%s\" not found.", src_port_name, src.name))
    assert(dst_port, string.format("Input port \"%s\" of block \"%s\" not found.", dst_port_name, dst.name))

    -- If this is a block to block connection in a top composite block
    if src ~= self and dst ~= self then
        assert(class.isinstanceof(src_port, block.OutputPort) or class.isinstanceof(src_port, block.AliasedOutputPort), string.format("Source port %s.%s is not an output port.", src_port.owner.name, src_port.name))
        assert(class.isinstanceof(dst_port, block.InputPort) or class.isinstanceof(dst_port, block.AliasedInputPort), string.format("Destination port %s.%s is not an input port.", dst_port.owner.name, dst_port.name))

        -- Assert input is not already connected
        assert(not self._connections[dst_port], string.format("Input port \"%s\" of block \"%s\" already connected.", dst_port.name, dst_port.owner.name))

        -- Update our connections table
        self._connections[dst_port] = src_port
        self._blocks[src] = true
        self._blocks[dst] = true

        debug.printf("[CompositeBlock] Connected output %s.%s to input %s.%s\n", src.name, src_port.name, dst.name, dst_port.name)
    else
        -- Otherwise, we are aliasing an input or output of a composite block

        -- Map src and dst ports to alias port and block port
        local alias_port = (src == self) and src_port or dst_port
        local target_port = (src == self) and dst_port or src_port

        if class.isinstanceof(alias_port, block.AliasedInputPort) and
                (class.isinstanceof(target_port, block.InputPort) or class.isinstanceof(target_port, block.AliasedInputPort)) then
            -- If we are aliasing a composite block input to a concrete block input

            assert(not self._connections[target_port], string.format("Input port %s.%s already connected.", target_port.owner.name, target_port.name))
            self._connections[target_port] = alias_port
            self._blocks[target_port.owner] = true

            debug.printf("[CompositeBlock] Aliased composite input %s.%s to block input %s.%s\n", alias_port.owner.name, alias_port.name, target_port.owner.name, target_port.name)
        elseif class.isinstanceof(alias_port, block.AliasedOutputPort) and
                (class.isinstanceof(target_port, block.OutputPort) or class.isinstanceof(target_port, block.AliasedOutputPort)) then
            -- If we are aliasing a composite block output to a concrete block output

            assert(not self._connections[alias_port], string.format("Output port %s.%s already connected.", alias_port.owner.name, alias_port.name))

            self._connections[alias_port] = target_port
            self._blocks[target_port.owner] = true

            debug.printf("[CompositeBlock] Aliased composite output %s.%s to block output %s.%s\n", alias_port.owner.name, alias_port.name, target_port.owner.name, target_port.name)
        else
            error("Malformed port connection.")
        end
    end
end

-- Helper functions to manipulate internal data structures

local function build_dependency_graph(connections)
    local graph = {}

    -- Add dependencies between connected blocks
    for input, output in pairs(connections) do
        if class.isinstanceof(input, block.AliasedOutputPort) or class.isinstanceof(output, block.AliasedInputPort) then
            goto continue
        end

        local src = output.owner
        local dst = input.owner

        if graph[src] == nil then
            graph[src] = {}
        end

        if graph[dst] == nil then
            graph[dst] = {src}
        else
            graph[dst][#graph[dst] + 1] = src
        end

        ::continue::
    end

    return graph
end

local function build_reverse_dependency_graph(connections)
    local graph = {}

    -- Add dependencies between connected blocks
    for input, output in pairs(connections) do
        local src = output.owner
        local dst = input.owner

        if graph[src] == nil then
            graph[src] = {dst}
        else
            graph[src][#graph[src] + 1] = dst
        end

        if graph[dst] == nil then
            graph[dst] = {}
        end
    end

    return graph
end

local function build_skip_set(connections)
    local dep_graph = build_reverse_dependency_graph(connections)
    local graph = {}

    -- Generate a set of downstream dependencies to block
    local function recurse_dependencies(block, set)
        set = set or {}

        for _, dependency in ipairs(dep_graph[block]) do
            set[dependency] = true
            recurse_dependencies(dependency, set)
        end

        return set
    end

    for block, _ in pairs(dep_graph) do
        graph[block] = recurse_dependencies(block)
    end

    return graph
end

local function build_evaluation_order(dependency_graph)
    local order = {}

    -- Copy dependency graph and count the number of blocks
    local graph_copy = {}
    local count = 0
    for k, v in pairs(dependency_graph) do
        graph_copy[k] = v
        count = count + 1
    end

    -- While we still have blocks left to add to our order
    while #order < count do
        for block, deps in pairs(graph_copy) do
            local deps_met = true

            -- Check if dependencies exists in order list
            for _, dep in pairs(deps) do
                if not util.array_exists(order, dep) then
                    deps_met = false
                    break
                end
            end

            -- If dependencies are met
            if deps_met then
                -- Add block next to the evaluation order
                order[#order + 1] = block
                -- Remove the block from the dependency graph
                graph_copy[block] = nil

                break
            end
        end
    end

    return order
end

-- Validation, Differentiation, and Initialization

function CompositeBlock:_validate_inputs()
    for block, _ in pairs(self._blocks) do
        for i=1, #block.inputs do
            assert(self._connections[block.inputs[i]] ~= nil, string.format("Block \"%s\" input \"%s\" is unconnected.", block.name, block.inputs[i].name))
        end

        if class.isinstanceof(block, CompositeBlock) then
            block:_validate_inputs()
        end
    end
end

function CompositeBlock:_differentiate()
    if not self._evaluation_order then
        self._evaluation_order = build_evaluation_order(build_dependency_graph(self._connections))
    end

    for _, block in ipairs(self._evaluation_order) do
        -- Gather input data types to this block
        local input_data_types = {}
        for _, input in ipairs(block.inputs) do
            input_data_types[#input_data_types+1] = self._connections[input].data_type
        end

        -- Differentiate the block
        block:differentiate(input_data_types)

        if class.isinstanceof(block, CompositeBlock) then
            block:_differentiate()
        end
    end

    -- Validate aliased output port types match concrete output port types
    if self.outputs then
        for _, composite_output in ipairs(self.outputs) do
            local block_output = self._connections[composite_output]
            assert(composite_output.data_type == block_output.data_type, string.format("Invalid type signature, composite output %s.%s data type %s does not match block output %s.%s data type %s.", self.name, composite_output.name, composite_output.data_type.type_name, block_output.owner.name, block_output.name, block_output.data_type.type_name))
        end
    end
end

function CompositeBlock:_crawl_connections(crawled_connections, composite_stack)
    crawled_connections = crawled_connections or {}
    composite_stack = composite_stack or {}

    if not self._evaluation_order then
        self._evaluation_order = build_evaluation_order(build_dependency_graph(self._connections))
    end

    local function resolve_port(port)
        if class.isinstanceof(port, block.OutputPort) then
            return port
        elseif class.isinstanceof(port, block.AliasedOutputPort) then
            return resolve_port(port.owner._connections[port])
        elseif class.isinstanceof(port, block.AliasedInputPort) then
            for _, composite in pairs(composite_stack) do
                if composite._connections[port] then
                    return resolve_port(composite._connections[port])
                end
            end
            error(string.format("Unexpected disconnected composite input port %s.%s", port.owner.name, port.name))
        else
            error(string.format("Unexpected port type for port %s.%s", port.owner.name, port.name))
        end
    end

    for _, block in pairs(self._evaluation_order) do
        if class.isinstanceof(block, CompositeBlock) then
            block:_crawl_connections(crawled_connections, {self, unpack(composite_stack)})
        else
            for _, input in ipairs(block.inputs) do
                crawled_connections[input] = resolve_port(self._connections[input])
            end
        end
    end

    return crawled_connections
end

function CompositeBlock:_connect_pipes(all_connections)
    for input, output in pairs(all_connections) do
        assert(class.isinstanceof(input, block.InputPort), string.format("Unexpected type for input port %s.%s", input.owner.name, input.name))
        assert(class.isinstanceof(output, block.OutputPort), string.format("Unexpected type for output port %s.%s", output.owner.name, output.name))

        -- Create a pipe from output to input
        local p = pipe.Pipe(output, input)
        -- Link the pipe to the input and output ends
        output.pipes[#output.pipes + 1] = p
        input.pipe = p
    end
end

function CompositeBlock:_validate_rates()
    if not self._evaluation_order then
        self._evaluation_order = build_evaluation_order(build_dependency_graph(self._connections))
    end

    -- Check all block input rates match
    for _, block in pairs(self._evaluation_order) do
        if class.isinstanceof(block, CompositeBlock) then
            block:_validate_rates()
        else
            local rate = nil
            for i=1, #block.inputs do
                if not rate then
                    rate = block.inputs[i].pipe:get_rate()
                else
                    assert(block.inputs[i].pipe:get_rate() == rate, string.format("Block \"%s\" input \"%s\" sample rate mismatch.", block.name, block.inputs[i].name))
                end
            end
        end
    end
end

function CompositeBlock:_initialize()
    if not self._evaluation_order then
        self._evaluation_order = build_evaluation_order(build_dependency_graph(self._connections))
    end

    for _, block in ipairs(self._evaluation_order) do
        block:initialize()
    end
end

function CompositeBlock:_prepare_to_run()
    -- Validate all block inputs are connected
    self:_validate_inputs()

    -- Differentiate all blocks
    self:_differentiate()

    -- Crawl connections
    local all_connections = self:_crawl_connections()

    -- Connect pipes
    self:_connect_pipes(all_connections)

    -- Validate all block input rates match
    self:_validate_rates(evaluation_order)

    -- Initialize all blocks
    self:_initialize()

    -- Determine global block evaluation order
    local evaluation_order = build_evaluation_order(build_dependency_graph(all_connections))

    -- Create and initialize control sockets
    for _, block in ipairs(evaluation_order) do
        block.control_socket = pipe.ControlSocket()
        block.control_socket:initialize()
    end

    -- Initialize all pipes
    for input, output in pairs(all_connections) do
        input.pipe:initialize()
    end

    debug.print("[CompositeBlock] Flow graph:")
    for _, k in ipairs(evaluation_order) do
        local s = string.gsub(tostring(k), "\n", "\n[CompositeBlock]\t")
        debug.print("[CompositeBlock]\t" .. s)
    end

    return all_connections, evaluation_order
end

-- Execution

ffi.cdef[[
    /* File descriptor table size */
    int getdtablesize(void);

    /* File tree walk */
    int ftw(const char *dirpath, int (*fn) (const char *fpath, const struct stat *sb, int typeflag), int nopenfd);
]]

local function listdir(path)
    local entries = {}

    -- Normalize directory path with trailing /
    path = (string.sub(path, -1) == "/") and path or (path .. "/")

    -- Store each file entry in entries
    local function store_entry_fn(fpath, sb, typeflag)
        if typeflag == 0 then
            entries[#entries + 1] = string.sub(ffi.string(fpath), #path+1)
        end
        return 0
    end

    -- File tree walk on directory path
    if ffi.C.ftw(path, store_entry_fn, 1) ~= 0 then
        error("ftw(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end

    return entries
end

---
-- Run a top-level block. This is equivalent to calling `start()` followed by
-- `wait()` on the top-level block.
--
-- @function CompositeBlock:run
-- @treturn CompositeBlock self
-- @raise Block already running error.
-- @raise Block input port unconnected error.
-- @raise Block input port sample rate mismatch error.
-- @raise No compatible type signatures found for block error.
--
-- @usage
-- -- Run a top-level block
-- top:run()
function CompositeBlock:run(multiprocess)
    self:start(multiprocess)
    self:wait()

    return self
end

---
-- Start a top-level block.
--
-- @function CompositeBlock:start
-- @treturn CompositeBlock self
-- @raise Block already running error.
-- @raise Block input port unconnected error.
-- @raise Block input port sample rate mismatch error.
-- @raise No compatible type signatures found for block error.
--
-- @usage
-- -- Start a top-level block
-- top:start()
function CompositeBlock:start(multiprocess)
    if self._running then
        error("CompositeBlock already running!")
    end

    -- Default to multiprocess
    multiprocess = (multiprocess == nil) and true or multiprocess

    -- Prepare to run
    local all_connections, evaluation_order = self:_prepare_to_run()

    -- If there's no blocks to run, return
    if #evaluation_order == 0 then
        return self
    end

    if multiprocess then
        self._pids = {}

        debug.printf("[CompositeBlock] Parent pid %d\n", ffi.C.getpid())

        -- Block handling of SIGINT and SIGCHLD
        local sigset = ffi.new("sigset_t[1]")
        ffi.C.sigemptyset(sigset)
        ffi.C.sigaddset(sigset, ffi.C.SIGINT)
        ffi.C.sigaddset(sigset, ffi.C.SIGCHLD)
        if ffi.C.sigprocmask(ffi.C.SIG_BLOCK, sigset, nil) ~= 0 then
            error("sigprocmask(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end

        -- Install dummy signal handler for SIGCHLD
        self._saved_sigchld_handler = ffi.C.signal(ffi.C.SIGCHLD, function (sig) end)

        -- Fork and run blocks
        for _, block in ipairs(evaluation_order) do
            local pid = ffi.C.fork()
            if pid < 0 then
                error("fork(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
            end

            if pid == 0 then
                -- Create a set of file descriptors to save
                local save_fds = {}

                -- Ignore SIGPIPE, handle with error from write()
                ffi.C.signal(ffi.C.SIGPIPE, ffi.cast("sighandler_t", ffi.C.SIG_IGN))

                -- Save control socket block fd
                save_fds[block.control_socket:fileno_block()] = true

                -- Save input pipe fds
                for i = 1, #block.inputs do
                    for _, fd in pairs(block.inputs[i]:filenos()) do
                        save_fds[fd] = true
                    end
                end

                -- Save output pipe fds
                for i = 1, #block.outputs do
                    for _, fd in pairs(block.outputs[i]:filenos()) do
                        save_fds[fd] = true
                    end
                end

                -- Save open file fds
                for file, _ in pairs(block.files) do
                    local fd = (type(file) == "number") and file or ffi.C.fileno(file)
                    save_fds[fd] = true
                end

                -- Close all other file descriptors
                if platform.os == "Linux" then
                    for _, entry in pairs(listdir("/proc/self/fd")) do
                        local fd = tonumber(entry)
                        if fd and not save_fds[fd] then
                            ffi.C.close(fd)
                        end
                    end
                else
                    -- Fall back to the nuclear approach, as FreeBSD and
                    -- Mac OS X may not have fdescfs or procfs mounted
                    for fd = 0, ffi.C.getdtablesize()-1 do
                        if not save_fds[fd] then
                            ffi.C.close(fd)
                        end
                    end
                end

                debug.printf("[CompositeBlock] Block %s pid %d\n", block.name, ffi.C.getpid())

                -- Run the block
                local status, err = xpcall(function () block:run() end, _G.debug.traceback)
                if not status then
                    io.stderr:write(string.format("[%s] Block runtime error: %s\n", block.name, tostring(err)))
                    os.exit(1)
                end

                -- Exit
                os.exit(0)
            else
                self._pids[block] = pid
            end
        end

        -- Close all pipe inputs and outputs in the top-level process
        for input, output in pairs(all_connections) do
            input:close()
            output:close()
        end

        -- Mark ourselves as running
        self._running = true
    else
        -- Build a skip set, containing the set of blocks to skip for each
        -- block, if it produces no new samples.
        local skip_set = build_skip_set(all_connections)

        -- Block handling of SIGINT
        local sigset = ffi.new("sigset_t[1]")
        ffi.C.sigemptyset(sigset)
        ffi.C.sigaddset(sigset, ffi.C.SIGINT)
        if ffi.C.sigprocmask(ffi.C.SIG_BLOCK, sigset, nil) ~= 0 then
            error("sigprocmask(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end

        -- Ignore SIGPIPE, handle with error from write()
        ffi.C.signal(ffi.C.SIGPIPE, ffi.cast("sighandler_t", ffi.C.SIG_IGN))

        -- Run blocks in round-robin order
        local running = true
        while running do
            local skip = {}

            for _, block in ipairs(evaluation_order) do
                if not skip[block] then
                    local ret = block:run_once()
                    if ret == false then
                        -- No new samples produced, mark downstream blocks in
                        -- our skip set
                        for b , _ in pairs(skip_set[block]) do
                            skip[b] = true
                        end
                    elseif ret == nil then
                        -- EOF reached, stop running
                        running = false
                        break
                    end
                end
            end

            -- Check for SIGINT
            if ffi.C.sigpending(sigset) ~= 0 then
                error("sigpending(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
            end
            if ffi.C.sigismember(sigset, ffi.C.SIGINT) == 1 then
                debug.print("[CompositeBlock] Received SIGINT. Shutting down...")
                running = false
            end
        end

        -- Clean up all blocks
        for _, block in ipairs(evaluation_order) do
            block:cleanup()
        end

        -- Unblock handling of SIGINT
        local sigset = ffi.new("sigset_t[1]")
        ffi.C.sigemptyset(sigset)
        ffi.C.sigaddset(sigset, ffi.C.SIGINT)
        if ffi.C.sigprocmask(ffi.C.SIG_UNBLOCK, sigset, nil) ~= 0 then
            error("sigprocmask(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end
    end

    return self
end

local function sigwait_timeout(sig, timeout)
    if ffi.os ~= "OSX" then
        -- Use sigtimedwait()

        -- Build signal set with signal
        local sigset = ffi.new("sigset_t[1]")
        ffi.C.sigemptyset(sigset)
        ffi.C.sigaddset(sigset, sig)

        -- Build timeout timespec
        local timespec = ffi.new("struct timespec[1]")
        timespec[0].tv_sec = 0
        timespec[0].tv_nsec = timeout * 1e9

        local ret = ffi.C.sigtimedwait(sigset, nil, timespec)
        if ret < 0 and ffi.errno() == ffi.C.EAGAIN then
            return false
        elseif ret < 0 then
            error("sigtimedwait(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end

        return true
    else
        -- Mac OS X doesn't have sigtimedwait(), so poll sigpending() with
        -- timeout

        local tic = platform.time_us()
        local sigset = ffi.new("sigset_t[1]")

        while true do
            -- Read pending signals
            if ffi.C.sigpending(sigset) ~= 0 then
                error("sigpending(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
            end

            -- Check if signal is pending
            if ffi.C.sigismember(sigset, sig) == 1 then
                break
            end

            -- Check timeout
            if (platform.time_us() - tic) > timeout then
                return false
            end

            ffi.C.usleep(math.floor(timeout / 100 * 1e6))
        end

        -- Consume the signal
        ffi.C.sigemptyset(sigset)
        ffi.C.sigaddset(sigset, sig)
        local sig_ret = ffi.new("int[1]")
        if ffi.C.sigwait(sigset, sig_ret) ~= 0 then
            error("sigwait(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
        end

        return true
    end
end

-- Reap child processes, consume SIGCHLD, and unblock signals
function CompositeBlock:_reap(timeout)
    local timed_out = false

    -- Loop waiting on all child processes to exit, killing them with SIGTERM
    -- if they don't exit on their own after a timeout
    while true do
        local all_exited = true

        for block, pid in pairs(self._pids) do
            -- If the process exists
            if ffi.C.kill(pid, 0) == 0 then
                -- Reap process
                local ret = ffi.C.waitpid(pid, nil, ffi.C.WNOHANG)
                if ret == 0 then
                    -- Process is still running
                    all_exited = false

                    -- If waiting for SIGCHLD timed out, kill the process
                    if timed_out then
                        debug.printf("[CompositeBlock] Killing unresponsive block %s pid %d\n", block.name, pid)
                        ret = ffi.C.kill(pid, ffi.C.SIGTERM)
                        if ret < 0 then
                            error("kill(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
                        end
                    end
                elseif ret < 0 then
                    error("waitpid(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
                end
            end
        end

        if all_exited then
            break
        end

        -- Wait for SIGCHLD with timeout
        timed_out = not sigwait_timeout(ffi.C.SIGCHLD, timeout or 0.100)
    end

    -- Restore SIGCHLD handler
    ffi.C.signal(ffi.C.SIGCHLD, self._saved_sigchld_handler)

    -- Unblock handling of SIGINT and SIGCHLD
    local sigset = ffi.new("sigset_t[1]")
    ffi.C.sigemptyset(sigset)
    ffi.C.sigaddset(sigset, ffi.C.SIGINT)
    ffi.C.sigaddset(sigset, ffi.C.SIGCHLD)
    if ffi.C.sigprocmask(ffi.C.SIG_UNBLOCK, sigset, nil) ~= 0 then
        error("sigprocmask(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end

    -- Mark ourselves as not running
    self._running = false
end

---
-- Get the status of a top-level block.
--
-- @function CompositeBlock:status
-- @treturn table Status information with fields: `running` (bool).
-- @usage
-- if top:status().running then
--     print('Still running...')
-- end
function CompositeBlock:status()
    if not self._running then
        return {running = false}
    end

    -- Check if any children are still running
    for _, pid in pairs(self._pids) do
        if ffi.C.waitpid(pid, nil, ffi.C.WNOHANG) == 0 then
            return {running = true}
        end
    end

    -- Reap child processes
    self:_reap()

    return {running = false}
end

---
-- Stop a top-level block and wait until it has finished.
--
-- @function CompositeBlock:stop
-- @usage
-- -- Start a top-level block
-- top:start()
-- -- Stop a top-level block
-- top:stop()
function CompositeBlock:stop()
    if not self._running then
        return
    end

    -- Close control sockets to shutdown blocks
    for block, pid in pairs(self._pids) do
        block.control_socket:close_host()
    end

    -- Reap child processes
    self:_reap()
end

---
-- Wait for a top-level block to finish, either by natural termination or by
-- `SIGINT`.
--
-- @function CompositeBlock:wait
-- @usage
-- -- Start a top-level block
-- top:start()
-- -- Wait for the top-level block to finish
-- top:wait()
function CompositeBlock:wait()
    if not self._running then
        return
    end

    -- Check if all child processes already exited
    local all_exited = util.array_all(util.table_values(self._pids), function (pid) return ffi.C.waitpid(pid, nil, ffi.C.WNOHANG) > 0 end)
    if all_exited then
        self:_reap()
        return
    end

    -- Build signal set with SIGINT and SIGCHLD
    local sigset = ffi.new("sigset_t[1]")
    ffi.C.sigemptyset(sigset)
    ffi.C.sigaddset(sigset, ffi.C.SIGINT)
    ffi.C.sigaddset(sigset, ffi.C.SIGCHLD)

    -- Wait for SIGINT or SIGCHLD
    local sig = ffi.new("int[1]")
    if ffi.C.sigwait(sigset, sig) ~= 0 then
        error("sigwait(): " .. ffi.string(ffi.C.strerror(ffi.errno())))
    end

    if sig[0] == ffi.C.SIGINT then
        debug.print("[CompositeBlock] Received SIGINT. Shutting down...")

        -- Forcibly stop
        self:stop()
    elseif sig[0] == ffi.C.SIGCHLD then
        debug.print("[CompositeBlock] Child exited. Shutting down...")

        -- Reap child processes
        self:_reap()
    end
end

return {CompositeBlock = CompositeBlock, _crawl_connections = crawl_connections, _build_dependency_graph = build_dependency_graph, _build_reverse_dependency_graph = build_reverse_dependency_graph, _build_evaluation_order = build_evaluation_order, _build_skip_set = build_skip_set}
