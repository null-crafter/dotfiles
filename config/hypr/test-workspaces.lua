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

hl = setmetatable({
  get_monitors = function() return fake_monitors end,
  get_workspaces = function() return fake_workspaces end,
  workspace_rule = function(t) table.insert(rules, t) end,
  on = function(ev, fn) handlers[ev] = handlers[ev] or {}; table.insert(handlers[ev], fn) end,
}, { __index = function() return stub() end })

local CFG = arg[1] or "/home/rei/.config/hypr/hyprland.lua"
package.path = "/home/rei/.config/hypr/?.lua;" .. package.path
dofile(CFG)

-- Recompute rules for a given set of connected monitors, as monitor.added would.
local function connect(mons)
  fake_monitors = mons
  rules = {}
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

-- Scenario A: boot docked at the desk. Leftmost (HDMI at x=0) must own 1-10.
connect({ HDMI, EDP })
check("A. docked boot: HDMI-A-1 owns 1-10",  block_of("HDMI-A-1"), 1)
check("A. docked boot: eDP-1 owns 11-20",    block_of("eDP-1"),    11)
check("A. exactly 20 rules",                 #rules,               20)

-- Scenario B: fresh session, undocked, then a projector appears to the LEFT (x=-1920).
-- Positional ordering alone would hand the projector block 1. Stickiness must not.
rules, handlers, fake_monitors = {}, {}, {}
dofile(CFG)

connect({ EDP })
check("B. undocked boot: eDP-1 owns 1-10",   block_of("eDP-1"),    1)

connect({ PROJ, EDP })
check("B. projector plugged: eDP-1 KEEPS 1-10", block_of("eDP-1"),    1)
check("B. projector gets 11-20",                block_of("BEAMER-1"), 11)

connect({ EDP })
check("B. projector unplugged: eDP-1 still 1-10", block_of("eDP-1"),  1)

-- Scenario C: three monitors, all distinct blocks.
connect({ PROJ, EDP, HDMI })
local seen = {}
for _, m in ipairs({ "eDP-1", "BEAMER-1", "HDMI-A-1" }) do seen[block_of(m)] = true end
local n = 0; for _ in pairs(seen) do n = n + 1 end
check("C. three monitors get three distinct blocks", n, 3)
check("C. 30 rules",                                 #rules, 30)

-- Scenario D: exactly one `default = true` per monitor.
local defaults = {}
for _, r in ipairs(rules) do
  if r.default then defaults[r.monitor] = (defaults[r.monitor] or 0) + 1 end
end
for _, m in ipairs({ "eDP-1", "BEAMER-1", "HDMI-A-1" }) do
  check("D. one default workspace on " .. m, defaults[m], 1)
end

-- Scenario E: config reload. Hyprland clears every workspace rule, wipes the Lua
-- state and re-executes this file -- with NO monitor event to follow. That is the
-- reported bug: with no rules, r~1 landed on workspace 2.
-- Real situation here: the laptop booted alone so it owns 1-10, while the external
-- is leftmost and owns 11-20 -- so positional ordering alone would flip them.
rules, handlers  = {}, {}
fake_monitors    = { HDMI, EDP }
fake_workspaces  = { ws(1, EDP), ws(2, EDP), ws(3, EDP), ws(11, HDMI) }
dofile(CFG)   -- the reload itself; no connect() call, no monitor event

check("E. reload recreates rules with no monitor event", #rules,               20)
check("E. reload: eDP-1 KEEPS 1-10 (no positional flip)", block_of("eDP-1"),    1)
check("E. reload: HDMI-A-1 keeps 11-20",                  block_of("HDMI-A-1"), 11)

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
