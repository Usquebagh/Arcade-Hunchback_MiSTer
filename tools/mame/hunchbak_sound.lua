-- SPDX-License-Identifier: BSD-3-Clause
-- Parameters are a runner-generated Lua table in the private output directory.
local cfg = dofile(assert(os.getenv('HUNCHBAK_CAPTURE_CONFIG')))
local machine = manager.machine
local main = assert(machine.devices[':maincpu'])
local audio = assert(machine.devices[':audiocpu'])
local program = assert(main.spaces.program)
local control = assert(main.spaces.data) -- S2650_CTRL_PORT = 0, NOT extended I/O
local taps, files = {}, {}
-- Pass-through handlers remove themselves on garbage collection.
_G.hunchbak_capture = {taps = taps}
local function output(name, header)
    local f = assert(io.open(cfg.output .. '/' .. name, 'w'))
    f:write(header .. '\n')
    files[#files + 1] = f
    return f
end
local function now() return machine.time:as_double() end
local events = output('dac-events.csv', 'seconds,audio_cpu_cycle,address,value')
local timeline = output('timeline.csv', 'seconds,command')
local status = output('lua-status.txt', 'hunchbak capture')
local injecting, unexpected = false, 0
local function retain(tap) taps[#taps + 1] = tap end
local function on_frame(callback)
    if emu.add_machine_frame_notifier then
        retain(emu.add_machine_frame_notifier(callback))
    else
        emu.register_frame(callback)
    end
end
local function on_stop(callback)
    if emu.add_machine_stop_notifier then
        retain(emu.add_machine_stop_notifier(callback))
    else
        emu.register_stop(callback)
    end
end
retain(audio.spaces.program:install_write_tap(0x1840, 0x1887, 'capture_dac', function(address, value)
    if now() < cfg.capture_seconds and (address == 0x1840 or address >= 0x1880) then
        local seconds = now()
        events:write(string.format('%.9f,%d,0x%04x,0x%02x\n', seconds,
            math.floor(seconds * cfg.cycle_hz), address, value))
    end
end))
retain(control:install_write_tap(0, 0, 'capture_command', function(_, value)
    if (cfg.mode == 'record' or injecting) and now() < cfg.capture_seconds then
        timeline:write(string.format('%.9f,0x%02x\n', now(), value))
    elseif cfg.mode == 'directed' and not injecting then
        unexpected = unexpected + 1
    end
end))

-- Neither tested Lua API exposes device_execute_interface::suspend. The read
-- overlay executes HALT at reset PC forever; II prevents vblank waking it.
-- No ROM region is changed and no game initialization is performed.
if cfg.mode == 'directed' then
    main.state.PS.value = main.state.PS.value | 0x2000
    retain(program:install_read_tap(0, 0x7fff, 'capture_main_halt', function() return 0x40 end))
    status:write('main_stop=HALT opcode read overlay at reset; PSU.II set\n')
end

local beepers = {}
for i = 0, 2 do
    if machine.devices[':beep' .. i] then beepers[#beepers + 1] = 'beep' .. i end
end
status:write('beepers_present=' .. table.concat(beepers, ',') .. '\n')
status:write('beepers_excluded=false\n')
-- Pinned Lua device_sound_interface has no per-output gain/clock setter.
-- The DAC event log retains every beep-affecting write (1840,1884..1887).

local inputs, positions
if cfg.mode == 'record' then
    inputs = output('inputs.csv', 'seconds,coin,start,right,jump')
    positions = output('sprite-positions.csv', 'seconds,pvi,object,x,y,right,jump')
    local fields = {}
    for _, spec in ipairs({{'coin', ':IN0', 0x08}, {'start', ':IN0', 0x01},
                          {'right', ':IN1', 0x10}, {'jump', ':IN0', 0x20}}) do
        local port = assert(machine.ioport.ports[spec[2]])
        for _, field in pairs(port.fields) do
            if field.mask == spec[3] then fields[spec[1]] = field end
        end
        assert(fields[spec[1]], 'missing input ' .. spec[1])
    end
    local right, jump = 0, 0
    -- Observe writes in the actual PVI bank (FLAG=0), never character RAM.
    -- S2636 object origins: 00,10,20,40; HC at +0a, VC at +0c.
    local coords = {}
    retain(program:install_write_tap(0, 0x7fff, 'capture_sprite', function(address, value)
        address = address & 0x1fff -- all four physical memory mirrors
        if now() >= cfg.capture_seconds or address < 0x1500 or address > 0x17ff or main.state.FO.value ~= 0 then return end
        local reg = address & 0xff
        for object, base in ipairs({0x00, 0x10, 0x20, 0x40}) do
            if reg == base + 0x0a or reg == base + 0x0c then
                local pvi = 0x17 - (address >> 8)
                local key = pvi * 4 + object
                local pair = coords[key] or {255, 255}
                pair[reg == base + 0x0a and 1 or 2] = value
                coords[key] = pair
                positions:write(string.format('%.9f,%d,%d,%d,%d,%d,%d\n',
                    now(), pvi, object - 1, pair[1], pair[2], right, jump))
            end
        end
    end))
    local previous = ''
    on_frame(function()
        local t = now()
        local coin = (t >= 3 and t < 3.2) and 1 or 0
        local start = (t >= 4 and t < 4.2) and 1 or 0
        right = t >= 15 and 1 or 0
        jump = (t >= 15 and (t - 15) % 1.2 < 0.18) and 1 or 0
        local values = {coin, start, right, jump}
        for i, name in ipairs({'coin', 'start', 'right', 'jump'}) do
            fields[name]:set_value(values[i]) -- logical pressed=1, even active-low
        end
        local signature = table.concat(values, ',')
        if signature ~= previous then
            inputs:write(string.format('%.9f,%s\n', t, signature))
            previous = signature
        end
    end)
end

on_stop(function()
    status:write(string.format('main_pc=0x%04x\n', main.state.PC.value))
    status:write(string.format('end_seconds=%.9f\nunexpected_main_commands=%d\n', now(), unexpected))
    for _, f in ipairs(files) do f:close() end
end)
status:write(string.format('start_seconds=%.9f\n', now()))
if cfg.mode == 'directed' then
    -- Autoboot is itself a coroutine. emu.wait uses scheduler timers, not frames.
    for _, entry in ipairs(cfg.timeline) do
        local delay = entry[1] - now()
        if delay > 0 then emu.wait(delay) end
        injecting = true
        control:write_u8(0, entry[2])
        injecting = false
    end
end
