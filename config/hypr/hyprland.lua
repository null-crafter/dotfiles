-- Hyprland 0.56.2 -- https://wiki.hypr.land/
require("monitors")

-- Resolved from package.path, which Hyprland prepends with the config dir
-- (ConfigManager.cpp:534-545). assert so a missing file fails loudly.
local MONITORS_FILE = assert(package.searchpath("monitors", package.path),
    "monitors.lua not found on package.path")

local term          = "kitty"
local dmenu         = "fuzzel"
local mod           = "SUPER" -- Meta / Win key
local fm            = "dolphin"

-- Talks to the running `noctalia --daemon`. When the daemon is down this exits 1
-- and prints to stderr -- but Hyprland's executor points the child's stderr at
-- /dev/null, so a dead daemon fails *silently*. SUPER+SHIFT+R restarts it.
local function noctalia(cmd)
    return hl.dsp.exec_cmd("noctalia msg " .. cmd)
end

-- Restart, or start if it isn't running. The single-instance guard is an flock in
-- $XDG_RUNTIME_DIR released on process exit, so wait for the old pid to go before
-- starting -- otherwise the new instance loses the race and exits "already running".
local noctalia_restart =
    "pkill -x noctalia; " ..
    "for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x noctalia >/dev/null || break; sleep 0.1; done; " ..
    "noctalia --daemon"

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
    general = { gaps_in = 5, gaps_out = 10, border_size = 2, layout = "master" },
    input   = { kb_layout = "us", follow_mouse = 1, repeat_delay = 200, repeat_rate = 35 },
    -- Wake the screens on pointer motion. Deliberately NOT key_press_enables_dpms:
    -- that listener fires on key *release* too, so it would undo SUPER+Escape the
    -- instant you let go. Nudge the mouse or trackpad to wake.
    misc    = { mouse_move_enables_dpms = true },
    -- SDR content is authored for gamma 2.2 displays, but the default pipeline
    -- decodes it with the sRGB curve, whose linear toe near black lifts the shadows
    -- -- grey blacks, washed-out mids. Treat non-colour-managed surfaces (nearly
    -- every app) as gamma 2.2 instead: Renderer.cpp:1932 only sets an explicit source
    -- curve for srgb/gamma22/gamma22force, and falls through on "default".
    render  = { cm_sdr_eotf = "gamma22" },
})

-- Noctalia owns the bar, notifications, lock screen, wallpaper and OSDs.
-- It ships no systemd unit, so the compositor starts it.
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia --daemon")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)

hl.bind(mod .. " + Return", hl.dsp.exec_cmd(term))
hl.bind(mod .. " + Space", noctalia("panel-toggle launcher"))
hl.bind(mod .. " + D", hl.dsp.exec_cmd(dmenu))
hl.bind(mod .. " + Tab", noctalia("window-switcher"))

hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mod .. " + E", hl.dsp.exec_cmd(fm))
hl.bind(mod .. " + C", hl.dsp.window.center())

-- Session: panel for the normal case, hard exit as the escape hatch.
hl.bind(mod .. " + M", noctalia("panel-toggle session"))
hl.bind(mod .. " + SHIFT + M", hl.dsp.exit())
hl.bind(mod .. " + Escape", hl.dsp.dpms({ action = "off" }))
hl.bind(mod .. " + SHIFT + Escape", noctalia("session lock"))
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd(noctalia_restart))

hl.bind(mod .. " + N", noctalia("panel-toggle control-center"))
hl.bind(mod .. " + comma", noctalia("settings-toggle"))

hl.bind("Print", noctalia("screenshot-region"))
hl.bind("SHIFT + Print", noctalia("screenshot-fullscreen"))
hl.bind("CTRL + Print", noctalia("screenshot-fullscreen all"))

for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ direction = dir }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end

-- 10 workspaces per monitor, never shared. Blocks go to monitors in role order --
-- the internal panel first when it is connected, then externals left to right --
-- and a monitor never loses a block it already holds. Nothing is reserved for an
-- absent panel: on a desktop or a clamshelled laptop that would leave workspaces
-- 1-10 bound to nothing, and r~N would hand them to every screen at once.
local PER_MONITOR  = 10
local blocks       = {}  -- monitor name -> block index, sticky within this Lua state
local last_applied = nil -- signature of the block->monitor map we last wrote rules for

-- DRM names built-in panels eDP-*/LVDS-*/DSI-*; anything else is external.
local function is_internal(name)
    return name:match("^eDP") or name:match("^LVDS") or name:match("^DSI")
end

local function by_position(a, b)
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y -- tiebreak for vertically stacked screens
end

-- A config reload wipes the Lua state (ConfigManager reinitLuaState), taking
-- `blocks` with it. Re-derive from where workspaces actually are so a reload never
-- renumbers a screen. Seeds only when empty, so a monitor Hyprland just auto-assigned
-- a workspace to cannot steal a block from an incumbent.
local function seed_blocks_from_live_state()
    if next(blocks) ~= nil then return end
    for _, ws in ipairs(hl.get_workspaces()) do
        local mon, id = ws.monitor, ws.id
        if mon and id and id > 0 then -- id > 0 skips special/named workspaces
            local b = math.floor((id - 1) / PER_MONITOR) + 1
            if not blocks[mon.name] or b < blocks[mon.name] then blocks[mon.name] = b end
        end
    end
end

-- block index -> monitor name
local function compute_owner()
    seed_blocks_from_live_state()

    local internal, external = {}, {}
    for _, mon in ipairs(hl.get_monitors()) do -- excludes mirrors and disabled outputs
        table.insert(is_internal(mon.name) and internal or external, mon)
    end
    table.sort(internal, by_position)
    table.sort(external, by_position)

    local ordered = {}
    for _, m in ipairs(internal) do ordered[#ordered + 1] = m end
    for _, m in ipairs(external) do ordered[#ordered + 1] = m end

    -- Honour blocks already held, then fill the gaps with the lowest free one, so
    -- closing the lid or plugging in a projector never renumbers a live screen.
    local taken = {}
    for _, m in ipairs(ordered) do
        local b = blocks[m.name]
        if b and not taken[b] then taken[b] = true else blocks[m.name] = nil end
    end
    for _, m in ipairs(ordered) do
        if not blocks[m.name] then
            local b = 1
            while taken[b] do b = b + 1 end
            blocks[m.name], taken[b] = b, true
        end
    end

    local owner = {}
    for _, m in ipairs(ordered) do owner[blocks[m.name]] = m.name end
    return owner
end

-- SUPER+ALT+Escape turns every external screen off, SUPER+ALT+grave brings them
-- back. Disabling the output makes the display see a real signal loss and drop to
-- standby, unlike the DPMS blank on SUPER+Escape which an HDMI monitor answers by
-- re-scanning its inputs and lighting its own panel back up.
-- (The other session binds are further up; these live here because they capture
-- is_internal, which must already be defined when hl.bind runs.)
hl.bind(mod .. " + ALT + Escape", function()
    local mons = hl.get_monitors() -- already excludes disabled outputs

    -- Keep block 1's monitor alive: the internal panel, or on a desktop/clamshell
    -- the leftmost screen. Disabling every output would leave no display at all.
    local keep = compute_owner()[1]
    if not keep then -- block 1 ownerless (lid shut, externals hold 2+ by stickiness)
        local leftmost = { table.unpack(mons) }
        table.sort(leftmost, by_position)
        keep = leftmost[1] and leftmost[1].name
    end

    for _, m in ipairs(mons) do
        if m.name ~= keep then
            hl.monitor({ output = m.name, disabled = true })
        end
    end
end)

hl.bind(mod .. " + ALT + grave", function()
    -- hl.monitor MERGES into the existing rule, and monitors.lua never mentions
    -- `disabled`, so re-applying it alone would leave disabled = true and the output
    -- would stay dark. Lua cannot enumerate disabled outputs, so take the names from
    -- the file itself: wrap hl.monitor for the duration of the dofile so every
    -- output it declares also gets disabled = false. An output the file marks
    -- disabled explicitly (nwg-displays writes that for ones you turned off in
    -- its UI) is left alone.
    local real = hl.monitor
    hl.monitor = function(t)
        if t.disabled == nil then t.disabled = false end
        return real(t)
    end
    local ok, err = pcall(dofile, MONITORS_FILE)
    hl.monitor = real -- restored even if the file errors
    if not ok then error(err, 0) end
end)

local function do_assign()
    local owner = compute_owner()

    -- Rewriting rules schedules REFRESH_MONITOR_STATES, which re-applies monitor rules
    -- and re-enables a DPMS-disabled output -- and that emits monitor.layout_changed,
    -- which lands right back here. Only touch the rules when the mapping really changed,
    -- so the cycle cannot start. (A config reload resets this with the Lua state, so the
    -- rules get written once after every reload, which is exactly when they are needed.)
    local sig = {}
    for block, name in pairs(owner) do sig[#sig + 1] = block .. "=" .. name end
    table.sort(sig)
    sig = table.concat(sig, ",")

    if sig ~= last_applied then
        last_applied = sig
        for block, name in pairs(owner) do
            local base = (block - 1) * PER_MONITOR
            for n = 1, PER_MONITOR do
                hl.workspace_rule({
                    workspace = tostring(base + n),
                    monitor   = name,
                    default   = (n == 1),
                })
            end
        end
    end

    -- Hyprland stamps m_lastMonitor on every workspace when a monitor disconnects and
    -- drags them all back on reconnect (Monitor.cpp onDisconnect/onConnect). That path
    -- ignores workspace rules, so put strays back where their block says they belong.
    for _, ws in ipairs(hl.get_workspaces()) do
        local id, cur = ws.id, ws.monitor
        if id and id > 0 and cur then -- id > 0 skips special/named workspaces
            local want = owner[math.floor((id - 1) / PER_MONITOR) + 1]
            if want and want ~= cur.name then
                hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = want }))
            end
        end
    end
end

-- Moving workspaces emits workspace.moveToMonitor / monitorChanged, and
-- hl.workspace_rule schedules REFRESH_MONITOR_STATES -- either could re-enter this
-- through monitor.layout_changed. A loop here would hang the compositor.
local applying = false
local function assign_workspaces()
    if applying then return end
    applying = true
    local ok, err = pcall(do_assign)
    applying = false -- released even on error, so no silent lockout
    if not ok then error(err, 0) end
end

hl.on("hyprland.start", assign_workspaces)
hl.on("monitor.added", assign_workspaces)
hl.on("monitor.removed", assign_workspaces)
hl.on("monitor.layout_changed", assign_workspaces)
hl.on("config.reloaded", assign_workspaces)

-- Rules are cleared on every reload and no monitor event follows, so recreate them
-- at load time as well. At first launch monitors are not enumerated yet and this is
-- a no-op; monitor.added covers that case.
assign_workspaces()

-- "r~N" is the Nth workspace available on the *focused* monitor. The rules above are
-- what make it skip the other monitors' blocks -- without them it degenerates to 1..10.
for i = 1, PER_MONITOR do
    local key = tostring(i % 10) -- workspace 10 lives on the 0 key
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = "r~" .. i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = "r~" .. i }))
end

-- "-1"/"+1" wrap through the monitor list relative to the focused one.
hl.bind(mod .. " + bracketleft", hl.dsp.focus({ monitor = "-1" }))
hl.bind(mod .. " + bracketright", hl.dsp.focus({ monitor = "+1" }))
hl.bind(mod .. " + SHIFT + bracketleft", hl.dsp.window.move({ monitor = "-1" }))
hl.bind(mod .. " + SHIFT + bracketright", hl.dsp.window.move({ monitor = "+1" }))

hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize())

-- Hardware keys via noctalia, so every change draws an OSD.
hl.bind("XF86AudioRaiseVolume", noctalia("volume-up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", noctalia("volume-down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", noctalia("volume-mute"), { locked = true })
hl.bind("XF86AudioMicMute", noctalia("mic-mute"), { locked = true })
hl.bind("XF86MonBrightnessUp", noctalia("brightness-up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", noctalia("brightness-down"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", noctalia("media toggle"), { locked = true })
hl.bind("XF86AudioNext", noctalia("media next"), { locked = true })
hl.bind("XF86AudioPrev", noctalia("media previous"), { locked = true })

hl.window_rule({
    name        = "mpv-no-auto-hdr",
    match       = { class = "^mpv$" },
    no_auto_hdr = true,
})
