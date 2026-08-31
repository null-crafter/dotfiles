-- Hyprland 0.56.2 -- https://wiki.hypr.land/
require("monitors")

local term  = "kitty"
local dmenu = "fuzzel"
local mod   = "SUPER" -- Meta / Win key
local fm    = "dolphin"

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
hl.bind(mod .. " + Escape", noctalia("session lock"))
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

-- 10 workspaces per monitor, never shared, no output names hardcoded.
-- Blocks are handed out left-to-right on first sight and then STAY PUT: a monitor
-- keeps the block it was given, so plugging in a projector mid-session never
-- renumbers the screen you are working on. Newcomers get the lowest free block.
local PER_MONITOR = 10
local blocks      = {} -- monitor name -> block index, sticky for the session

-- A config reload wipes the whole Lua state (ConfigManager reinitLuaState), taking
-- `blocks` with it. Re-derive it from where workspaces actually are, so a reload
-- never renumbers the screen you are working on. Only seeds when empty, so a newly
-- connected monitor that Hyprland auto-assigned a workspace to cannot steal a block.
local function seed_blocks_from_live_state()
    if next(blocks) ~= nil then return end
    for _, ws in ipairs(hl.get_workspaces()) do
        local mon, id = ws.monitor, ws.id
        if mon and id and id > 0 then -- id > 0 skips special/named workspaces
            local b = math.floor((id - 1) / PER_MONITOR) + 1
            if not blocks[mon.name] or b < blocks[mon.name] then
                blocks[mon.name] = b
            end
        end
    end
end

local function assign_workspaces()
    seed_blocks_from_live_state()

    local mons = hl.get_monitors() -- already excludes mirrors and disabled outputs
    table.sort(mons, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y -- tiebreak for vertically stacked screens
    end)

    -- Honour remembered blocks that are still free; drop the rest for reassignment.
    local taken = {}
    for _, mon in ipairs(mons) do
        local b = blocks[mon.name]
        if b and not taken[b] then
            taken[b] = true
        else
            blocks[mon.name] = nil
        end
    end

    for _, mon in ipairs(mons) do
        if not blocks[mon.name] then
            local b = 1
            while taken[b] do b = b + 1 end
            blocks[mon.name] = b
            taken[b] = true
        end
    end

    for _, mon in ipairs(mons) do
        local base = (blocks[mon.name] - 1) * PER_MONITOR
        for i = 1, PER_MONITOR do
            hl.workspace_rule({
                workspace = tostring(base + i),
                monitor   = mon.name,
                default   = (i == 1),
            })
        end
    end
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
