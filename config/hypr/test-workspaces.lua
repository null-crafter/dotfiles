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

hl = setmetatable({
  get_monitors = function() return fake_monitors end,
  get_workspaces = function() return fake_workspaces end,
  workspace_rule = function(t) table.insert(rules, t) end,
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

-- Scenario F: no internal panel (lid closed while docked, or a desktop).
-- Block 1 stays reserved, so the external keeps 11-20 rather than sliding to 1-10.
fake_workspaces = {}
connect({ HDMI })
check("F. no internal: external still owns 11-20", block_of("HDMI-A-1"), 11)
check("F. no internal: block 1 left unassigned",   block_of("eDP-1"),    nil)
check("F. only 10 rules",                          #rules,               10)

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

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
