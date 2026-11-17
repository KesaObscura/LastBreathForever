-- Run from the addon folder: lua5.1 tests/run.lua
local dir = arg[0]:match("^(.*)run%.lua$") or "./"
local root = dir .. "../"
local tests, failed = {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local M
local function fresh(opts)
  LastBreathForeverDB = opts and opts.db or nil
  M = dofile(dir .. "mock_wow.lua")
  if opts and opts.setup then opts.setup(M) end
  local ns = M.load(root)
  M.fire("ADDON_LOADED", "LastBreathForever")
  M.fire("PLAYER_ENTERING_WORLD")
  return ns
end
-- the cell on screen (white or red text visible); two at once would be a bug
local function cell(ns)
  local found
  for _, c in ipairs(ns.cells) do
    if M.visible(c.textN) or M.visible(c.textU) then
      assert(not found, "two estimates on screen at once")
      found = c
    end
  end
  return found
end
local function seconds(ns)
  local c = cell(ns)
  local t = c and M.reveal(c.textN:GetText())
  return t and tonumber(t:match("~(%d+)"))
end
local function shown(ns) return cell(ns) ~= nil end
local function white(ns) local c = cell(ns) return c and M.visible(c.textN) and not M.visible(c.textU) end
local function red(ns) local c = cell(ns) return c and M.visible(c.textU) and not M.visible(c.textN) end
local function near(a, b, tol, msg)
  if not a or math.abs(a - b) > tol then error(string.format("%s: expected %s, got %s", msg or "", b, tostring(a)), 2) end
end
-- a fight: pull, then `hits` hits one second apart, losing `rate` of the health per second
local function fight(n, rate)
  M.combat = true
  M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, n do
    M.hp = M.hp - rate
    M.hit()
    M.tick(1, 0)
  end
end

test("every text exists in all 9 languages with the same placeholders", function()
  local ns = fresh()
  local T = ns.LOCALES
  local n = 0
  for loc, t in pairs(T) do
    n = n + 1
    for k, en in pairs(T.enUS) do
      local v = t[k]
      assert(type(v) == "string" and v ~= "", loc .. " lacks " .. k)
      local a, b = {}, {}
      for p in en:gmatch("%%[%d%.]*[dsf]") do a[#a + 1] = p end
      for p in v:gmatch("%%[%d%.]*[dsf]") do b[#b + 1] = p end
      assert(table.concat(a, " ") == table.concat(b, " "), loc .. "." .. k .. ": placeholders differ")
    end
    for k in pairs(t) do assert(T.enUS[k], loc .. " has the unknown key " .. k) end
  end
  assert(n == 10, "9 languages and esMX expected, got " .. n)
  assert(T.esMX == T.esES)
end)

test("the version in the TOC is the version in the code", function()
  local ns = fresh()
  local toc = io.open(root .. "LastBreathForever.toc"):read("*a")
  assert(toc:match("## Version: ([%d%.]+)") == ns.VERSION)
end)

test("nothing shows before three hits and two seconds", function()
  local ns = fresh()
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  M.tick(1, 0)
  assert(not shown(ns), "no hit yet")
  M.hp = 0.95 M.hit() M.tick(0.4, 0)
  M.hp = 0.90 M.hit() M.tick(3, 0)
  assert(not shown(ns), "two hits are not enough")
  M.hp = 0.85 M.hit() M.tick(0.2, 0)
  assert(shown(ns), "three hits, more than two seconds: show")
end)

test("the seconds are right for steady damage (5 % per second)", function()
  local ns = fresh()
  fight(8, 0.05)                 -- 60 % left, 12 more hits to go
  M.now = M.now - 1 M.tick(0.2, 0)
  near(seconds(ns), 12, 1, "seconds")
  assert(shown(ns))
end)

test("a boss joined at 50 %: seconds show once it has lost enough, and they are about right", function()
  local ns = fresh()
  M.hp = 0.52
  fight(3, 0.02)                                  -- 46 %: its band is 50-55 %, too little lost yet
  assert(not shown(ns), "only a few percent lost since joining: nothing yet")
  for _ = 1, 8 do M.hp = M.hp - 0.02 M.hit() M.tick(1, 0) end   -- 30 %, 2 % per second
  M.now = M.now - 1 M.tick(0.2, 0)
  assert(shown(ns), "22 % lost since joining: show")
  near(seconds(ns), 15, 3, "30 % left at 2 % per second")
end)

test("joined at every share from 100 % to 20 %: one estimate, within a quarter at half way", function()
  for start = 100, 21, -1 do
    local ns = fresh()
    M.hp = start / 100
    local rate = M.hp / 40                        -- dies 40 s after joining
    M.combat = true M.fire("PLAYER_REGEN_DISABLED")
    for _ = 1, 20 do M.hp = M.hp - rate M.hit() M.tick(1, 0) end
    M.now = M.now - 1 M.tick(0.2, 0)
    local sec = seconds(ns)
    assert(sec, "joined at " .. start .. " %: nothing on screen at half way")
    assert(math.abs(sec - 20) <= 5, "joined at " .. start .. " %: " .. sec .. " s shown, 20 s left")
  end
end)

test("a target first hit below 20 % shows nothing", function()
  local ns = fresh()
  M.hp = 0.18
  fight(6, 0.02)
  assert(not shown(ns))
end)

test("a boss the group hit first (98 %) still shows", function()
  local ns = fresh()
  M.hp = 0.98
  fight(6, 0.03)
  assert(shown(ns))
end)

test("open world: a target met again in the same fight keeps its count", function()
  local ns = fresh()
  fight(6, 0.05)                                  -- mob-1 at 70 %
  local hp1 = M.hp
  M.target.guid, M.hp = "mob-2", 1
  M.fire("PLAYER_TARGET_CHANGED")
  M.tick(1, 0)
  assert(not shown(ns), "new target: nothing yet")
  M.target.guid, M.hp = "mob-1", hp1
  M.fire("PLAYER_TARGET_CHANGED")
  M.tick(0.2, 0)
  assert(shown(ns), "back on the first target: its seconds are back at once")
  near(seconds(ns), 7 * 0.7 / 0.3, 3, "seconds from the old count")
end)

test("dungeon: targets cannot be told apart, so a target met again starts anew", function()
  local ns = fresh({ setup = function(m) m.secretGuid = true end })
  fight(6, 0.05)
  local hp1 = M.hp
  M.hp = 1 M.fire("PLAYER_TARGET_CHANGED") M.tick(1, 0)
  M.hp = hp1 M.fire("PLAYER_TARGET_CHANGED") M.tick(1, 0)
  assert(not shown(ns))
  for _ = 1, 3 do M.hit() M.tick(1, 0.005) end
  assert(not shown(ns), "it starts anew at 70 %: nothing until it has lost enough again")
end)

test("after the fight everything is forgotten", function()
  local ns = fresh()
  fight(6, 0.05)
  M.combat = false M.fire("PLAYER_REGEN_ENABLED")
  M.tick(0.4, 0)
  assert(not shown(ns))
  for _, s in ipairs(ns.slots) do assert(s.hits == 0 and s.hit == nil) end
end)

test("'Show from': hidden while more than the limit is left", function()
  local ns = fresh({ db = { limit = 30 } })
  fight(5, 0.01)                                  -- 95 % after 5 s: about 100 s left
  assert(not shown(ns), "100 s left, limit 30 s")
  M.tick(20, 0.04)                                -- 15 % left
  assert(shown(ns), "a few seconds left")
end)

test("'Show from: Always' still hides a target that has lost next to nothing", function()
  local ns = fresh({ db = { limit = 0 } })
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  M.hp = 0.999
  for _ = 1, 4 do M.hit() M.tick(1, 0) end
  assert(not shown(ns))
  M.hp = 0.9 M.tick(0.2, 0)
  assert(shown(ns))
end)

test("'Last seconds in red': white above the mark, red below", function()
  local ns = fresh({ db = { urgent = 5, limit = 0 } })
  fight(8, 0.05)                                  -- about 12 s left
  assert(white(ns), "white at 12 s")
  M.tick(9, 0.05)                                 -- about 3 s left
  assert(red(ns), "red at 3 s")
  ns.db.urgent = 0
  M.tick(0.2, 0)
  assert(white(ns), "switched off: white")
end)

test("'Last seconds in red' goes up to 60 s (cooldowns kept for the end)", function()
  local ns = fresh({ db = { urgent = 60, limit = 0 } })
  assert(ns.db.urgent == 60, "60 is a valid choice")
  fight(10, 0.005)                                -- 95 %: about 190 s left
  assert(white(ns), "white at 190 s")
  M.tick(30, 0.02)                                -- 35 % after 40 s: about 20 s left
  assert(red(ns), "red below 60 s")
end)

test("'Only elites and bosses'", function()
  local ns = fresh({ db = { elite = true } })
  fight(6, 0.05)
  assert(not shown(ns), "a normal mob")
  M.target.class = "elite"
  M.tick(0.2, 0)
  assert(shown(ns), "an elite")
end)

test("friendly, dead or no target: nothing", function()
  local ns = fresh()
  fight(6, 0.05)
  M.target.dead = true M.tick(0.2, 0)
  assert(not shown(ns), "dead")
  M.target.dead, M.target.hostile = false, false
  M.fire("PLAYER_TARGET_CHANGED") M.tick(0.2, 0)
  assert(not shown(ns), "friendly")
end)

test("misses and heals on the target do not count as hits", function()
  local ns = fresh()
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _, a in ipairs({ "MISS", "HEAL", "DODGE", "WOUND", "MISS" }) do
    M.fire("UNIT_COMBAT", "target", a) M.tick(1, 0.02)
  end
  assert(not shown(ns))
  M.fire("UNIT_COMBAT", "target", M.secret("WOUND")) M.tick(1, 0)
  assert(not shown(ns), "a secret action is not read")
end)

test("no secret is touched and no warning is printed in a whole fight", function()
  local ns = fresh()
  fight(8, 0.05)
  M.tick(8, 0.05)
  M.target.dead = true M.tick(0.4, 0)
  M.combat = false M.fire("PLAYER_REGEN_ENABLED")
  for _, m in ipairs(M.chat) do error("unexpected chat line: " .. m) end
  local _ = ns
end)

test("a client without the curve API: one warning, nothing shown, no error", function()
  local ns = fresh({ setup = function(m) m.noCurves = true end })
  fight(6, 0.05)
  assert(not shown(ns))
  assert(#M.chat == 1, "one warning expected, got " .. #M.chat)
end)

test("broken saved settings are replaced by the defaults", function()
  local ns = fresh({ db = { scale = "big", limit = 77, urgent = -1, icon = 5, point = "x" } })
  local d = ns.db
  assert(d.scale == 1 and d.limit == 300 and d.urgent == 5 and d.icon == true and d.point == nil)
end)

test("unlocked: a sample shows, a fight locks the frame again", function()
  local ns = fresh()
  SlashCmdList.LASTBREATHFOREVER("unlock")
  assert(ns.db.locked == false)
  M.hp = 0.5 M.hit() M.hit() M.hit() M.tick(3, 0)
  assert(not shown(ns), "the real seconds are hidden while unlocked")
  M.hp = 1
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  assert(ns.db.locked == true, "auto-lock at the pull")
  SlashCmdList.LASTBREATHFOREVER("unlock")
  assert(ns.db.locked == true, "no unlocking in a fight")
end)

test("dragging keeps the place when the size changes", function()
  local ns = fresh()
  ns.db.scale = 2
  ns.Apply()
  M.center = { 300, 200 }                          -- in the frame's own (doubled) units
  ns.hud.scripts.OnDragStop(ns.hud)
  assert(ns.db.point[1] == 600 and ns.db.point[2] == 400, "kept in screen units")
  ns.db.scale = 1
  ns.Apply()
  assert(ns.hud.point[4] == 600 and ns.hud.point[5] == 400)
  SlashCmdList.LASTBREATHFOREVER("reset")
  assert(ns.db.point == nil)
end)

test("settings: every control has a tooltip, also the greyed-out ones", function()
  local ns = fresh()
  ns.ToggleOptions()
  local win = ns.optionsWindow
  assert(win and win:IsShown())
  assert(#win.controls >= 14, "controls: " .. #win.controls)
  for i, c in ipairs(win.controls) do
    assert(c.scripts.OnEnter and c.tipTitle and c.tipText and c.tipText ~= "", "control " .. i .. " has no tooltip")
    c.scripts.OnEnter(c)
    assert(#GameTooltip.lines == 2)
    if c.kind == "Button" or c.kind == "CheckButton" then
      assert(c.motionWhileDisabled, "control " .. i .. ": no tooltip while greyed out")
    end
  end
  ns.ToggleOptions()
  assert(not win:IsShown())
end)

test("settings: steppers walk their lists and stop at the ends", function()
  local ns = fresh()
  ns.ToggleOptions()
  local c = ns.optionsWindow.controls
  -- 2/3 size, 5/6 limit, 8/9 urgent (minus, plus)
  for _ = 1, 10 do c[6].scripts.OnClick(c[6]) end
  assert(ns.db.limit == 600 and not c[6]:IsEnabled())
  for _ = 1, 10 do c[5].scripts.OnClick(c[5]) end
  assert(ns.db.limit == 0 and not c[5]:IsEnabled())
  for _ = 1, 40 do c[3].scripts.OnClick(c[3]) end
  assert(ns.db.scale == 3 and ns.hud:GetScale() == 3)
  for _ = 1, 40 do c[2].scripts.OnClick(c[2]) end
  assert(ns.db.scale == 0.5)
  for _ = 1, 9 do c[8].scripts.OnClick(c[8]) end
  assert(ns.db.urgent == 0)
  for _ = 1, 9 do c[9].scripts.OnClick(c[9]) end
  assert(ns.db.urgent == 60)
end)

test("the addon menu at the minimap opens the settings and has a tooltip", function()
  local ns = fresh()
  LastBreathForever_OnCompartmentEnter(nil, UIParent)
  assert(#GameTooltip.lines == 2 and GameTooltip.lines[1]:find("Last Breath Forever v" .. ns.VERSION, 1, true))
  LastBreathForever_OnCompartmentClick()
  assert(ns.optionsWindow:IsShown())
end)

test("it works in every language (seconds text keeps its number)", function()
  for _, loc in ipairs({ "deDE", "ruRU", "esES", "esMX", "frFR", "ptBR", "koKR", "zhCN", "zhTW" }) do
    local ns = fresh({ setup = function(m) m.locale = loc end })
    fight(8, 0.05)
    M.now = M.now - 1 M.tick(0.2, 0)
    near(seconds(ns), 12, 1, loc)
    ns.ToggleOptions()
  end
end)

for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then io.write("ok   ", t.name, "\n") else failed = failed + 1 io.write("FAIL ", t.name, "\n     ", tostring(err), "\n") end
end
io.write(string.format("\n%d tests, %d failed\n", #tests, failed))
os.exit(failed == 0 and 0 or 1)
