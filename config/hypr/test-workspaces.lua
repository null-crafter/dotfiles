-- Drives the REAL ~/.config/hypr/hyprland.lua with a stubbed `hl`, then exercises
-- the sticky block assignment through the scenarios that matter.

local rules, handlers = {}, {}
local fake_monitors, fake_workspaces = {}, {}

local function mon(name, x, y)
  return { name = name, x = x, y = y or 0 }
end

-- A live workspace: id sitting on monitor m.
local function ws(id, m)
  return { id = id, monitor = m }
end

-- Any hl.<anything> / hl.dsp.<a>.<b> resolves to a callable no-op.
local function stub()
  return setmetatable({}, {
    __index = function() return stub() end,
    __call  = function() return stub() end,
  })
end

-- hl.dsp.workspace.move is real so enforcement moves can be captured; everything
-- else under hl.dsp falls through to the no-op stub.
local moves = {}
local dsp_workspace = setmetatable({
  move = function(t) return { __move = t } end,
}, { __index = function() return stub() end })
local dsp = setmetatable({ workspace = dsp_workspace },
                         { __index = function() return stub() end })

local binds, monitor_calls = {}, {}

hl = setmetatable({
  get_monitors = function() return fake_monitors end,
  get_workspaces = function() return fake_workspaces end,
  workspace_rule = function(t) table.insert(rules, t) end,
  monitor = function(t) table.insert(monitor_calls, t) end,
  bind = function(key, fn) if type(fn) == "function" then binds[key] = fn end end,
  on = function(ev, fn) handlers[ev] = handlers[ev] or {}; table.insert(handlers[ev], fn) end,
  dsp = dsp,
  dispatch = function(m)
    if type(m) == "table" and m.__move then table.insert(moves, m.__move) end
  end,
}, { __index = function() return stub() end })

local CFG = arg[1] or "/home/rei/.config/hypr/hyprland.lua"
package.path = "/home/rei/.config/hypr/?.lua;" .. package.path
dofile(CFG)

-- Recompute rules for a given set of connected monitors, as monitor.added would.
local function connect(mons)
  fake_monitors = mons
  rules, moves = {}, {}
  for _, fn in ipairs(handlers["monitor.added"]) do fn() end
end

-- name -> sorted list of workspace ids bound to it
local function layout()
  local out = {}
  for _, r in ipairs(rules) do
    out[r.monitor] = out[r.monitor] or {}
    table.insert(out[r.monitor], tonumber(r.workspace))
  end
  for _, v in pairs(out) do table.sort(v) end
  return out
end

local function block_of(name)
  local l = layout()[name]
  return l and l[1] or nil          -- first workspace id identifies the block
end

local fails = 0
local function check(label, got, want)
  local ok = got == want
  if not ok then fails = fails + 1 end
  print(string.format("%-58s %-6s got=%s want=%s", label, ok and "PASS" or "FAIL",
        tostring(got), tostring(want)))
end

local HDMI, EDP, PROJ = mon("HDMI-A-1", 0), mon("eDP-1", 1920), mon("BEAMER-1", -1920)

-- Scenario A: boot docked. The INTERNAL panel owns 1-10 even though the external
-- sits to its left -- position no longer decides block 1.
connect({ HDMI, EDP })
check("A. docked boot: eDP-1 (internal) owns 1-10", block_of("eDP-1"),    1)
check("A. docked boot: HDMI-A-1 owns 11-20",        block_of("HDMI-A-1"), 11)
check("A. exactly 20 rules",                        #rules,               20)

-- Scenario B: undocked, then a projector appears to the LEFT (x=-1920).
-- The laptop must keep 1-10 no matter where the projector physically sits.
connect({ EDP })
check("B. undocked: eDP-1 owns 1-10",           block_of("eDP-1"),    1)

connect({ PROJ, EDP })
check("B. projector plugged: eDP-1 KEEPS 1-10", block_of("eDP-1"),    1)
check("B. projector gets 11-20",                block_of("BEAMER-1"), 11)

connect({ EDP })
check("B. projector unplugged: eDP-1 still 1-10", block_of("eDP-1"),  1)

-- Scenario C: three monitors. Internal takes 1-10; the two externals take 11-20 and
-- 21-30, ordered left to right (BEAMER at -1920 before HDMI at 0).
connect({ PROJ, EDP, HDMI })
check("C. internal owns 1-10",                block_of("eDP-1"),    1)
check("C. leftmost external owns 11-20",      block_of("BEAMER-1"), 11)
check("C. next external owns 21-30",          block_of("HDMI-A-1"), 21)
check("C. 30 rules",                          #rules,               30)

-- Scenario D: exactly one `default = true` per monitor.
local defaults = {}
for _, r in ipairs(rules) do
  if r.default then defaults[r.monitor] = (defaults[r.monitor] or 0) + 1 end
end
for _, m in ipairs({ "eDP-1", "BEAMER-1", "HDMI-A-1" }) do
  check("D. one default workspace on " .. m, defaults[m], 1)
end

-- Scenario E: config reload. Hyprland clears every workspace rule, wipes the Lua
-- state and re-executes this file -- with NO monitor event to follow. Regression
-- guard for the bug where r~1 landed on workspace 2 because no rules existed.
rules, handlers, moves = {}, {}, {}
fake_monitors    = { HDMI, EDP }
fake_workspaces  = { ws(1, EDP), ws(2, EDP), ws(3, EDP), ws(11, HDMI) }
dofile(CFG)   -- the reload itself; no connect() call, no monitor event

check("E. reload recreates rules with no monitor event", #rules,               20)
check("E. reload: eDP-1 keeps 1-10",                     block_of("eDP-1"),    1)
check("E. reload: HDMI-A-1 keeps 11-20",                 block_of("HDMI-A-1"), 11)

-- Scenario F: lid closes on a session that was docked. HDMI already holds block 2
-- from the scenarios above, and stickiness must keep it there -- sliding down to
-- 1-10 would renumber a live screen. (Booting straight into clamshell is different
-- and gets 1-10; that is scenario J.)
fake_workspaces = {}
connect({ HDMI })
check("F. lid shuts: external keeps the block it held", block_of("HDMI-A-1"), 11)
check("F. vacated block 1 left unassigned",             block_of("eDP-1"),    nil)
check("F. only 10 rules",                               #rules,               10)

-- Scenario G: enforcement. Hyprland's RETURNING path drags workspaces 1-10 onto the
-- external on reconnect, ignoring rules. They must be moved back to the internal.
fake_workspaces = { ws(1, HDMI), ws(2, HDMI), ws(11, HDMI), ws(12, EDP) }
connect({ HDMI, EDP })

local moved = {}
for _, m in ipairs(moves) do moved[m.workspace] = m.monitor end
check("G. stray ws 1 moved back to internal",  moved["1"],  "eDP-1")
check("G. stray ws 2 moved back to internal",  moved["2"],  "eDP-1")
check("G. stray ws 12 moved to its external", moved["12"], "HDMI-A-1")
check("G. correctly-placed ws 11 not moved",   moved["11"], nil)

-- Scenario H: the loop-breaker. Writing workspace rules schedules REFRESH_MONITOR_STATES,
-- which re-applies monitor rules (waking a DPMS-disabled output) and then emits
-- monitor.layout_changed -- straight back into this handler. A second pass over an
-- UNCHANGED monitor set must write zero rules, or the cycle never stops.
-- Fresh Lua state, and no monitors at load time so the load-time call writes nothing.
rules, handlers, moves = {}, {}, {}
fake_monitors, fake_workspaces = {}, {}
dofile(CFG)

connect({ HDMI, EDP })                        -- first pass: mapping is new
local first = #rules

rules = {}
for _, fn in ipairs(handlers["monitor.layout_changed"]) do fn() end
check("H. first pass writes the rules",           first,   20)
check("H. unchanged monitors write ZERO rules",   #rules,  0)

-- ...but a real monitor change must still write them.
rules = {}
fake_monitors = { EDP }
for _, fn in ipairs(handlers["monitor.layout_changed"]) do fn() end
check("H. a real change still writes rules",      #rules,  10)

-- Scenario I: SUPER+ALT+Escape disables every external screen by turning the OUTPUT
-- off (a DPMS blank lets an HDMI display relight itself); SUPER+ALT+grave restores.
-- Two separate keys, no toggle -- you press them blind, so each must be deterministic.
local screens_off = binds["SUPER + ALT + Escape"]
local screens_on  = binds["SUPER + ALT + grave"]
check("I. disable bind exists", type(screens_off), "function")
check("I. restore bind exists", type(screens_on),  "function")

fake_monitors, monitor_calls = { EDP, HDMI, PROJ }, {}
screens_off()
local disabled = {}
for _, c in ipairs(monitor_calls) do
  if c.disabled then disabled[c.output] = true end
end
check("I. external HDMI-A-1 disabled",       disabled["HDMI-A-1"], true)
check("I. external BEAMER-1 disabled",       disabled["BEAMER-1"], true)
check("I. internal eDP-1 NEVER disabled",    disabled["eDP-1"],    nil)

-- Restore. hl.monitor merges into the existing rule and monitors.lua never mentions
-- `disabled`, so the restore has to inject disabled = false or the output stays dark
-- forever. The stub stands in for monitors.lua: two plain outputs, plus one
-- nwg-displays deliberately turned off.
local real_dofile, restored = dofile, nil
local hl_monitor_before = hl.monitor
dofile = function(p)
  restored = p
  hl.monitor({ output = "eDP-1",    mode = "a" })
  hl.monitor({ output = "HDMI-A-1", mode = "b" })
  hl.monitor({ output = "OFF-1",    mode = "c", disabled = true })
end
fake_monitors, monitor_calls = { EDP }, {}
screens_on()
dofile = real_dofile

local flag = {}
for _, c in ipairs(monitor_calls) do flag[c.output] = c.disabled end
check("I. restore re-applies monitors.lua",
      (restored or ""):match("monitors%.lua$") ~= nil, true)
check("I. restore RE-ENABLES HDMI-A-1",        flag["HDMI-A-1"], false)
check("I. restore re-enables eDP-1",           flag["eDP-1"],    false)
check("I. output nwg marked off stays off",    flag["OFF-1"],    true)
check("I. hl.monitor wrapper not leaked",      hl.monitor == hl_monitor_before, true)

-- Scenario J: machines with no internal panel. Nothing is reserved for an absent
-- panel, so the first monitor gets 1-10 -- otherwise workspaces 1-10 are bound to
-- nothing and r~N hands them to every screen at once.
local DP1, DP2 = mon("DP-1", 0), mon("DP-2", 2560)

local function block_map()
  local out, bound = {}, {}
  for _, r in ipairs(rules) do
    local id = tonumber(r.workspace)
    out[r.monitor] = math.min(out[r.monitor] or 1e9, id)
    bound[id] = true
  end
  return out, bound
end

local function fresh(mons)
  rules, handlers, moves = {}, {}, {}
  fake_monitors, fake_workspaces = {}, {}
  dofile(CFG)
  connect(mons)
end

fresh({ DP1, DP2 })                                   -- desktop
local b, bound = block_map()
check("J. desktop: leftmost owns 1-10",   b["DP-1"], 1)
check("J. desktop: second owns 11-20",    b["DP-2"], 11)
check("J. desktop: ws 1-10 ARE bound",    bound[1],  true)

fresh({ HDMI, DP1 })                                  -- clamshell, lid shut
local c, cbound = block_map()
check("J. clamshell: first external owns 1-10", c["HDMI-A-1"], 1)
check("J. clamshell: ws 1-10 ARE bound",        cbound[1],     true)

-- Scenario K: stickiness. Assign with the lid open, then close it: the external
-- must KEEP the block it already held rather than sliding down to 1-10, or every
-- lid close would renumber the screen and drag windows across monitors.
fresh({ EDP, HDMI })
local k1 = block_map()
check("K. lid open: eDP-1 owns 1-10",     k1["eDP-1"],    1)
check("K. lid open: HDMI-A-1 owns 11-20", k1["HDMI-A-1"], 11)

rules = {}
fake_monitors = { HDMI }                              -- lid shuts, eDP disappears
for _, fn in ipairs(handlers["monitor.added"]) do fn() end
local k2 = block_map()
check("K. lid shut: HDMI-A-1 KEEPS 11-20", k2["HDMI-A-1"], 11)

-- Scenario L: on a panel-less machine the screens-off bind must leave one output
-- alive, or the session ends up with no display at all.
fresh({ DP1, DP2 })
monitor_calls = {}
binds["SUPER + ALT + Escape"]()
local off = 0
for _, cc in ipairs(monitor_calls) do if cc.disabled then off = off + 1 end end
check("L. desktop: outputs left alive", #fake_monitors - off, 1)

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
