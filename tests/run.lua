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
  if not (opts and opts.cycle) then ns.CYCLE = 0 end -- every update a full cycle (the game: 0.4 s)
  M.fire("ADDON_LOADED", "LastBreathForever")
  M.fire("PLAYER_ENTERING_WORLD")
  return ns
end
-- the cell on screen (any of its texts visible); two at once would be a bug
local function anyText(c)
  for _, fs in ipairs({ c.textN, c.textU, c.textL, c.textM }) do
    if M.visible(fs) then return fs end
  end
end
local function cell(ns)
  local found
  for _, c in ipairs(ns.cells) do
    if anyText(c) then
      assert(not found, "two estimates on screen at once")
      found = c
    end
  end
  return found
end
-- the seconds on screen, whatever the form ("~12 s", "~2:30", "~12 min")
local function seconds(ns)
  local c = cell(ns)
  local t = c and M.reveal(anyText(c):GetText())
  if not t then return nil end
  local m, d = t:match("^~(%d+):(%d)0$")
  if m then return tonumber(m) * 60 + tonumber(d) * 10 end
  local n = t:match("^~(%d+) min$")
  if n then return tonumber(n) * 60 end
  return tonumber(t:match("~(%d+)"))
end
local function shown(ns) return cell(ns) ~= nil end
local function white(ns) local c = cell(ns) return c and not M.visible(c.textU) end
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
  -- a checkout has no build commit; a packaged build shows "0.2.0 (abc1234)"
  assert(ns.BUILD == nil and ns.VERSION_TEXT == ns.VERSION)
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
  for _, s in ipairs(ns.targetSlots) do assert(s.hits == 0 and s.hit == nil) end
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
  fight(10, 0.006)                                -- 94 %: about 157 s left
  assert(white(ns), "white at 157 s")
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
  assert(#M.chat == 2, "one warning and the bug link expected, got " .. #M.chat)
  assert(M.chat[2]:find("LastBreathForever/issues", 1, true))
end)

test("broken saved settings are replaced by the defaults", function()
  local ns = fresh({ db = { scale = "big", limit = 77, urgent = -1, icon = 5, point = "x", shots = "yes" } })
  local d = ns.db
  assert(d.scale == 1 and d.limit == 300 and d.urgent == 10 and d.icon == true and d.point == nil)
  assert(d.shots == nil, "a broken test switch is dropped")
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
  assert(#win.controls == 52, "controls: " .. #win.controls)
  local py = win.widgets.plateY
  py.plus.scripts.OnClick(py.plus)
  assert(ns.db.plateY == 8, "height: steps of 2")
  for _ = 1, 40 do py.plus.scripts.OnClick(py.plus) end
  assert(ns.db.plateY == 60 and not py.plus:IsEnabled(), "height: up to 60")
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
  local rows = ns.optionsWindow.widgets.leftRows
  -- 2/3 size, 5/6 limit, 8/9 urgent (minus, plus), counted from 2 as before
  local c = { false }
  for i, x in ipairs(rows) do c[i + 1] = x end
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
  c[9].scripts.OnClick(c[9])
  assert(ns.db.urgent == 5, "no 3 s step any more")
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

-- the cell of the focus frame that is on screen
local function focusSeconds(ns)
  for _, c in ipairs(ns.views[2].cells) do
    local fs = anyText(c)
    if fs then
      local t = M.reveal(fs:GetText())
      local m, d = t:match("^~(%d+):(%d)0$")
      if m then return tonumber(m) * 60 + tonumber(d) * 10 end
      return tonumber(t:match("~(%d+)"))
    end
  end
end
local ALLY = { exists = true, hostile = false, guid = "ally" }
local function boss() return { exists = true, hostile = true, guid = "boss", class = "elite", level = 30, hp = 1 } end

test("the game does not say whether target and boss are the same: the target still works", function()
  local ns = fresh({ setup = function(m) m.secretSame = true end })
  local b = boss()
  M.bosses[1] = b
  M.target, M.hp = b, 1
  M.fire("ENCOUNTER_START", 592)
  M.fire("PLAYER_TARGET_CHANGED")
  fight(8, 0.05)
  M.now = M.now - 1 M.tick(0.2, 0)
  near(seconds(ns), 12, 1, "from the target's own count")
  assert(#M.chat == 0)
end)

test("focus frame: off by default; on: the focus' seconds while something else is the target", function()
  local ns = fresh()
  local f = boss()
  M.focus = f
  M.fire("PLAYER_FOCUS_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 10 do f.hp = f.hp - 0.04 M.hit(f) M.tick(1, 0) end     -- 60 % after 10 s
  assert(not focusSeconds(ns), "switched off: no second frame")
  assert(not M.visible(ns.views[2].hud))
  ns.db.focus = true
  ns.Apply()
  M.tick(0.2, 0)
  near(focusSeconds(ns), 15, 2, "focus: 60 % left at 4 % per second")
  assert(not shown(ns), "the target (a fresh mob) shows nothing yet")
end)

test("target and focus are the same mob: both frames show the same seconds, from the longer count", function()
  local ns = fresh({ db = { focus = true } })
  local f = boss()
  M.focus = f
  M.fire("PLAYER_FOCUS_CHANGED")
  M.target = ALLY
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  M.fire("PLAYER_TARGET_CHANGED")
  for _ = 1, 10 do f.hp = f.hp - 0.04 M.hit(f) M.tick(1, 0) end
  M.target, M.hp = f, f.hp
  M.fire("PLAYER_TARGET_CHANGED")
  M.tick(0.2, 0)
  assert(shown(ns), "the focus becomes the target: seconds at once, not after three new hits")
  assert(seconds(ns) == focusSeconds(ns), "both frames agree")
  -- and it stays one count: hits are not doubled
  local hits = ns.focusTrack.hits
  M.hit(f)
  assert(ns.focusTrack.hits == hits + 1)
end)

test("a new focus starts anew", function()
  local ns = fresh({ db = { focus = true } })
  local f = boss()
  M.focus = f
  M.fire("PLAYER_FOCUS_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 10 do f.hp = f.hp - 0.04 M.hit(f) M.tick(1, 0) end
  assert(focusSeconds(ns))
  M.focus = boss()
  M.fire("PLAYER_FOCUS_CHANGED")
  M.tick(0.4, 0)
  assert(not focusSeconds(ns))
end)

test("unlocked with the focus frame: two plates, each keeps its own place", function()
  local ns = fresh({ db = { focus = true } })
  SlashCmdList.LASTBREATHFOREVER("unlock")
  local v1, v2 = ns.views[1], ns.views[2]
  assert(M.visible(v1.plate) and M.visible(v2.plate))
  M.center = { 500, 300 }
  v2.hud.scripts.OnDragStop(v2.hud)
  assert(ns.db.focusPoint[1] == 500 and ns.db.point == nil)
  ns.db.focus = false
  ns.Apply()
  assert(not M.visible(v2.plate), "switched off: no second plate")
end)

test("test builds: /lbf shots takes screenshots in boss fights, every 10 s, then switches off", function()
  local ns = fresh()
  local n = 0
  Screenshot = function() n = n + 1 end
  SlashCmdList.LASTBREATHFOREVER("shots")
  assert(ns.db.shots == true)
  M.fire("ENCOUNTER_START", 592)
  M.target, M.hp = boss(), 1 M.fire("PLAYER_TARGET_CHANGED")
  fight(25, 0.01)
  assert(n == 3, "25 s: three screenshots, got " .. n)
  SlashCmdList.LASTBREATHFOREVER("shots")
  M.tick(20, 0)
  assert(n == 3 and ns.db.shots == nil, "off")
  Screenshot = nil
end)

test("/lbf check: one line per fight, no names, no secrets", function()
  local ns = fresh()
  local b = boss()
  M.bosses[1] = b
  M.target, M.hp = b, 1
  M.fire("ENCOUNTER_START", 592)
  M.fire("PLAYER_TARGET_CHANGED")
  fight(8, 0.05)
  M.fire("ENCOUNTER_END", 592)
  M.combat = false M.fire("PLAYER_REGEN_ENABLED")
  local list = ns.db.checks
  assert(#list == 2, "boss line and fight line, got " .. #list)
  assert(list[1]:find("boss enc=592", 1, true) and list[1]:find("target[hits=8", 1, true), list[1])
  assert(list[1]:find("fighting%[y=%d+ n=%d+ %?=0%]"), list[1])
  assert(list[1]:find("same%[y=%d+ n=0 %?=0%]"), list[1])
  assert(list[1]:find("plates%[.* shown=%d+ kept=%d+ reset=%d+%]"), list[1])
  for _, l in ipairs(list) do assert(type(l) == "string" and not issecretvalue(l) and not l:find("boss\"")) end
  SlashCmdList.LASTBREATHFOREVER("check")
  assert(#M.chat == 4, "title, two lines, the bug link")
  for _ = 1, 40 do ns.CheckLine("x") end
  assert(#ns.db.checks == 30, "the list stays short")
end)

test("focus frame follows the target's settings until it gets its own", function()
  local ns = fresh({ db = { focus = true, limit = 0, scale = 1.5 } })
  local v2 = ns.views[2]
  assert(ns.db.focusSame == true and ns.Cfg(v2) == ns.db, "same as the target by default")
  assert(v2.hud:GetScale() == 1.5)
  local f = boss()
  M.focus = f
  M.fire("PLAYER_FOCUS_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 5 do f.hp = f.hp - 0.012 M.hit(f) M.tick(1, 0) end      -- about 80 s left
  assert(focusSeconds(ns), "target's rule 'always': shown")
  ns.db.focusSame = false
  ns.db.f.limit, ns.db.f.scale = 30, 0.8
  ns.Apply()
  M.tick(0.2, 0)
  assert(not focusSeconds(ns), "its own rule '30 s': hidden at 80 s")
  assert(v2.hud:GetScale() == 0.8 and ns.views[1].hud:GetScale() == 1.5, "each frame its own size")
  assert(v2.cells[1].frame:GetScale() == 0.8, "the seconds take the frame's size")
end)

test("settings: the focus column is greyed out while it follows the target", function()
  local ns = fresh()
  ns.ToggleOptions()
  local w = ns.optionsWindow.widgets
  local focusRows = w.rightRows
  local function anyEnabled()
    for _, x in ipairs(focusRows) do
      if (x.kind == "Button" or x.kind == "CheckButton") and x:IsEnabled() then return true end
    end
  end
  assert(not w.sameAs:IsEnabled(), "no focus frame: 'same settings' is greyed out")
  assert(not anyEnabled(), "no focus frame: its rows are greyed out")
  w.show.checked = true w.show.scripts.OnClick(w.show)
  assert(ns.db.focus and w.sameAs:IsEnabled() and not anyEnabled(), "follows the target: rows greyed out")
  w.sameAs.checked = false w.sameAs.scripts.OnClick(w.sameAs)
  assert(anyEnabled(), "its own settings: rows can be used")
  -- its size stepper changes only the focus frame
  local plus = focusRows[2]
  plus.scripts.OnClick(plus)
  assert(ns.db.f.scale == 1.1 and ns.db.scale == 1)
end)

test("no estimate until the target has lost 5 % (the first seconds are too unsure)", function()
  local ns = fresh({ db = { limit = 0 } })
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 6 do M.hp = M.hp - 0.007 M.hit() M.tick(1, 0) end   -- 95.8 %
  assert(not shown(ns), "4 % lost: nothing")
  M.hp = 0.94 M.tick(0.2, 0)
  assert(shown(ns), "6 % lost: shown")
end)

test("language: chosen in the settings, the window and the frames switch at once", function()
  local ns = fresh()
  ns.ToggleOptions()
  local w = ns.optionsWindow.widgets
  assert(M.reveal(w.lang:GetText()) == "Game language")
  w.lang.Select("ruRU")
  assert(ns.db.language == "ruRU")
  local win = ns.optionsWindow
  assert(win:IsShown(), "the window stays open, built anew")
  assert(win.widgets.lang:GetText() == "Русский")
  assert(win.widgets.lock:GetText() == "Разблокировать")
  assert(ns.views[1].drag:GetText() == "Перетащи меня")
  ns.views[1].hud.scripts.OnDragStop(ns.views[1].hud) -- nothing breaks with the new texts
  win.widgets.lang.Select("auto")
  assert(ns.db.language == "auto" and ns.optionsWindow.widgets.lock:GetText() == "Unlock")
  -- the choice is kept: the next login starts in it
  ns.db.language = "deDE"
  local db = ns.db
  local ns2 = fresh({ db = db })
  ns2.ToggleOptions()
  assert(ns2.optionsWindow.widgets.lock:GetText() == "Entsperren")
  local ns3 = fresh({ db = { language = "xxXX" } })
  assert(ns3.db.language == "auto", "an unknown language falls back to the game's")
end)

test("the settings window keeps its place", function()
  local ns = fresh()
  ns.ToggleOptions()
  M.lt = { 300, 700 }
  ns.optionsWindow.scripts.OnDragStop(ns.optionsWindow)
  assert(ns.db.optPoint[1] == 300 and ns.db.optPoint[2] == 700)
  local ns2 = fresh({ db = ns.db })
  ns2.ToggleOptions()
  local p = ns2.optionsWindow.point
  assert(p[1] == "TOPLEFT" and p[4] == 300 and p[5] == 700, "opens where it was left")
end)

test("unlocked: the words and buttons around the frame keep their size at any frame size", function()
  local ns = fresh({ db = { scale = 0.5 } })
  SlashCmdList.LASTBREATHFOREVER("unlock")
  local v = ns.views[1]
  assert(v.hud:GetScale() == 0.5)
  assert(v.chrome.parent == UIParent and v.chrome:GetScale() == 1, "not scaled with the frame")
  assert(M.visible(v.drag) and v.drag.parent == v.chrome)
  local edges = 0
  for _, f in ipairs(M.frames) do
    if f.kind == "Texture" and f.parent == v.chrome then edges = edges + 1 end
  end
  assert(edges == 4, "the outline is drawn at full size, got " .. edges)
  SlashCmdList.LASTBREATHFOREVER("lock")
  assert(not M.visible(v.drag), "gone when locked")
end)

local function waiting(ns)
  for _, c in ipairs(ns.cells) do
    if M.visible(c.waitIcon) or M.visible(c.waitText) then return true end
  end
  return false
end

test("while counting without a number: a dim icon, then the number", function()
  local ns = fresh({ db = { limit = 0 } })
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  M.tick(1, 0)
  assert(not waiting(ns) and not shown(ns), "no hit yet: nothing")
  M.hp = 0.99 M.hit() M.tick(0.4, 0)
  assert(waiting(ns) and not shown(ns), "first hit: the dim icon")
  M.hp = 0.98 M.hit() M.tick(1, 0)
  M.hp = 0.97 M.hit() M.tick(1.4, 0)
  assert(waiting(ns) and not shown(ns), "3 % lost: still the dim icon")
  M.hp = 0.94 M.tick(0.2, 0)
  assert(shown(ns) and not waiting(ns), "6 % lost: the number, no dim icon")
  ns.db.icon = false ns.Apply()
  M.target.dead = true M.tick(0.2, 0)
  assert(not waiting(ns) and not shown(ns), "dead: nothing")
end)

test("group: the number waits for 10 s and 3 %, or 20 % lost", function()
  local ns = fresh({ db = { limit = 0 }, setup = function(m) m.group = 5 end })
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 6 do M.hp = M.hp - 0.01 M.hit() M.tick(1, 0) end     -- 94 % after 6 s
  assert(not shown(ns) and waiting(ns), "group, 6 % lost after 6 s: wait")
  for _ = 1, 5 do M.hp = M.hp - 0.01 M.hit() M.tick(1, 0) end     -- 89 % after 11 s
  assert(shown(ns), "after 10 s and 3 %: shown")
  near(seconds(ns), 89, 12, "1 % per second")
  -- a quick boss: 20 % in 5 s shows at once
  local ns2 = fresh({ db = { limit = 0 }, setup = function(m) m.group = 5 end })
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 5 do M.hp = M.hp - 0.045 M.hit() M.tick(1, 0) end    -- 77.5 % after 5 s
  assert(shown(ns2), "22.5 % lost: shown before 10 s")
end)

test("a target already fighting at 91 % is not taken for full (no halved number)", function()
  local ns = fresh({ db = { limit = 0 } })
  -- a new mob, already in the fight (the tank's AoE took it to 91 %)
  M.target = { exists = true, hostile = true, guid = "mob-2", fighting = true }
  M.hp = 0.91
  M.fire("PLAYER_TARGET_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 10 do M.hp = M.hp - 0.01 M.hit() M.tick(1, 0) end    -- 81 %, 1 % per second
  M.now = M.now - 1 M.tick(0.2, 0)
  near(seconds(ns), 81, 12, "about 81 s left (taken for full: about 40)")
end)

test("a target taken out of combat counts as full; the game not saying: narrow bands, still right", function()
  local ns = fresh({ db = { limit = 0 } })
  fight(10, 0.01)                                                 -- 90 %
  M.now = M.now - 1 M.tick(0.2, 0)
  near(seconds(ns), 90, 6, "full")
  local ns2 = fresh({ db = { limit = 0 }, setup = function(m) m.noCombatInfo = true end })
  fight(10, 0.01)
  M.now = M.now - 1 M.tick(0.2, 0)
  near(seconds(ns2), 99, 15, "the game did not say: from the 97.5-100 % band, about 12 % high")
end)

-- the text on screen, whichever of the three forms it is in
local function text(ns)
  for _, c in ipairs(ns.cells) do
    for _, fs in ipairs({ c.textN, c.textU, c.textL, c.textM }) do
      if M.visible(fs) then return M.reveal(fs:GetText()) end
    end
  end
end

test("long times read as minutes: ~2:30 above 90 s, ~12 min above 10 min", function()
  local ns = fresh({ db = { limit = 0 } })
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  -- 0.25 % per second: from 90 % after 40 s, 360 s are left
  for _ = 1, 40 do M.hp = M.hp - 0.0025 M.hit() M.tick(1, 0) end
  M.tick(1.2, 0)
  local t = text(ns)
  assert(t and t:match("^~%d:%d0$"), "m:ss expected, got " .. tostring(t))
  local m, d = t:match("^~(%d):(%d)0$")
  near(tonumber(m) * 60 + tonumber(d) * 10, 360, 45, "about 6 minutes")
  -- slower: 6 % in 60 s, about 15-16 minutes left
  local ns2 = fresh({ db = { limit = 0 } })
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 60 do M.hp = M.hp - 0.001 M.hit() M.tick(1, 0) end
  M.tick(1.2, 0)
  local t2 = text(ns2)
  assert(t2 and t2:match("^~%d+ min$"), "minutes expected, got " .. tostring(t2))
  near(tonumber(t2:match("%d+")), 16, 2, "about 16 minutes")
  -- and below 90 s plain seconds again
  local ns3 = fresh({ db = { limit = 0 } })
  fight(8, 0.05)
  M.now = M.now - 1 M.tick(0.2, 0)
  assert(text(ns3):match("^~%d+ s$"), text(ns3))
end)

test("'Show from' 1 min: never minutes", function()
  local ns = fresh({ db = { limit = 60 } })
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 40 do M.hp = M.hp - 0.0025 M.hit() M.tick(1, 0) end
  M.tick(1.2, 0)
  assert(text(ns) == nil, "6 min left, shown from 1 min: nothing")
end)

-- a mob of a dungeon pull (the game hides who is who there)
local function mob(guid) return { exists = true, hostile = true, guid = guid, class = "elite", level = 30, hp = 1 } end

test("nameplates: the boss is counted while an add is the target; its seconds at once", function()
  local ns = fresh({ db = { limit = 0 }, setup = function(m) m.secretGuid = true m.group = 5 end })
  local b, add = mob("boss"), mob("add")
  M.showPlate(1, b) M.showPlate(2, add)
  M.target, M.hp = add, 1
  M.fire("PLAYER_TARGET_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 20 do b.hp = b.hp - 0.02 M.hit(b) add.hp = add.hp - 0.04 M.hp = add.hp M.hit(add) M.tick(1, 0) end
  -- boss 60 % after 20 s: about 30 s left; take it into the target
  M.target, M.hp = b, b.hp
  M.fire("PLAYER_TARGET_CHANGED")
  M.tick(0.2, 0)
  assert(shown(ns), "the boss's seconds at once, from its nameplate's count")
  near(seconds(ns), 30, 4, "boss")
  -- and back to the add (20 % left): its seconds at once too, also in a dungeon
  M.target, M.hp = add, add.hp
  M.fire("PLAYER_TARGET_CHANGED")
  M.tick(0.2, 0)
  near(seconds(ns), 5, 2, "add")
end)

test("target, focus and nameplate are one mob: one count, the same seconds in both frames", function()
  local ns = fresh({ db = { limit = 0, focus = true, onPlate = false }, setup = function(m) m.secretGuid = true end })
  local b = mob("boss")
  M.showPlate(1, b)
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 10 do b.hp = b.hp - 0.03 M.hit(b) M.tick(1, 0) end   -- counted by its nameplate only
  M.focus = b M.fire("PLAYER_FOCUS_CHANGED")
  M.target, M.hp = b, b.hp M.fire("PLAYER_TARGET_CHANGED")
  for _ = 1, 3 do b.hp = b.hp - 0.03 M.hp = b.hp M.hit(b) M.tick(1, 0) end
  M.tick(0.2, 0)
  local a, f = seconds(ns), focusSeconds(ns)
  assert(a and f and a == f, "both frames the same: " .. tostring(a) .. " / " .. tostring(f))
  near(a, 61 / 3, 3, "from the nameplate's count of 13 s, not the 3 s of the target and focus")
  assert(ns.views[1].track == ns.views[2].track and ns.views[1].track == ns.plateTracks.nameplate1,
    "one track for both frames")
end)

test("nameplates off, or no hits for them: the target and focus work as before", function()
  local ns = fresh({ db = { limit = 0, plates = false } })
  local b = mob("boss") M.showPlate(1, b)
  M.target, M.hp = b, 1 M.fire("PLAYER_TARGET_CHANGED")
  fight(8, 0.05)
  M.now = M.now - 1 M.tick(0.2, 0)
  near(seconds(ns), 12, 1, "plates off")
  assert(next(ns.plateTracks) == nil)
  local ns2 = fresh({ db = { limit = 0 }, setup = function(m) m.noPlateHits = true end })
  local b2 = mob("boss2") M.showPlate(1, b2)
  M.target, M.hp = b2, 1 M.fire("PLAYER_TARGET_CHANGED")
  fight(8, 0.05)
  M.now = M.now - 1 M.tick(0.2, 0)
  near(seconds(ns2), 12, 1, "no hits for plates")
end)

test("a nameplate that goes away forgets its count; a fight's end forgets them all", function()
  local ns = fresh({ db = { limit = 0 } })
  local b = mob("x") M.showPlate(1, b)
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 5 do b.hp = b.hp - 0.05 M.hit(b) M.tick(1, 0) end
  assert(ns.plateTracks.nameplate1.hits == 5)
  M.hidePlate(1)
  assert(ns.plateTracks.nameplate1 == nil)
  M.showPlate(1, b)
  assert(ns.plateTracks.nameplate1.hits == 0, "seen again: a new count")
  M.hit(b)
  M.combat = false M.fire("PLAYER_REGEN_ENABLED")
  assert(ns.plateTracks.nameplate1.hits == 0)
end)

test("/lbf check counts the nameplates", function()
  local ns = fresh()
  local b = mob("x") M.showPlate(1, b)
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  M.hit(b) M.hit(b)
  M.target, M.hp = b, 1 M.fire("PLAYER_TARGET_CHANGED")
  M.combat = false M.fire("PLAYER_REGEN_ENABLED")
  local l = ns.db.checks[#ns.db.checks]
  assert(l:find("plates%[seen=1 hits=2 target y=1"), l)
end)

test("a nameplate seen later than the target's own count does not replace it", function()
  local ns = fresh({ db = { limit = 0 } })
  local b = mob("x")
  M.target, M.hp = b, 1 M.fire("PLAYER_TARGET_CHANGED")
  fight(8, 0.05)                                  -- the target's own count: 8 s
  b.hp = M.hp
  M.showPlate(1, b)                               -- its nameplate comes into view only now
  b.hp = b.hp - 0.05 M.hp = b.hp M.hit(b)
  M.tick(0.2, 0)
  assert(shown(ns), "the longer count stays")
  near(seconds(ns), 11, 2, "from the target's own count")
end)

local function plateText(ns, token)
  local v = ns.plateViews[token]
  if not v then return nil end
  for _, c in ipairs(v.cells) do
    local fs = anyText(c)
    if fs then return M.reveal(fs:GetText()) end
  end
end

test("target, focus and nameplates all on: seconds everywhere, the same mob shows the same number", function()
  local ns = fresh({ db = { limit = 0, focus = true, plateSame = true }, setup = function(m) m.secretGuid = true m.group = 5 end })
  local b, a1, a2 = mob("boss"), mob("add1"), mob("add2")
  M.showPlate(1, b) M.showPlate(2, a1) M.showPlate(3, a2)
  M.target, M.hp = a1, 1 M.fire("PLAYER_TARGET_CHANGED")
  M.focus = b M.fire("PLAYER_FOCUS_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 12 do
    b.hp = b.hp - 0.02 M.hit(b)
    a1.hp = a1.hp - 0.04 M.hp = a1.hp M.hit(a1)
    a2.hp = a2.hp - 0.05 M.hit(a2)
    M.tick(1, 0)
  end
  M.tick(0.4, 0)
  local function num(t) return t and tonumber(t:match("%d+")) end
  local tgt, foc = seconds(ns), focusSeconds(ns)
  local p1, p2, p3 = num(plateText(ns, "nameplate1")), num(plateText(ns, "nameplate2")), num(plateText(ns, "nameplate3"))
  assert(tgt and foc and p1 and p2 and p3, "all five numbers on screen: " .. table.concat({ tostring(tgt), tostring(foc), tostring(p1), tostring(p2), tostring(p3) }, " "))
  assert(p2 == tgt, "the target's nameplate shows the target's number: " .. p2 .. " / " .. tgt)
  assert(p1 == foc, "the focus's nameplate shows the focus's number: " .. p1 .. " / " .. foc)
  assert(ns.plateViews.nameplate2.track == ns.views[1].track, "one count for the target")
  assert(ns.plateViews.nameplate1.track == ns.views[2].track, "one count for the focus")
  -- the focus becomes the target too: three places, one number
  M.target, M.hp = b, b.hp M.fire("PLAYER_TARGET_CHANGED")
  M.tick(0.4, 0)
  assert(seconds(ns) == focusSeconds(ns) and seconds(ns) == num(plateText(ns, "nameplate1")))
  assert(ns.views[1].track == ns.views[2].track and ns.views[2].track == ns.plateViews.nameplate1.track)
  -- switched off
  ns.db.allPlates = false ns.Apply() M.tick(0.4, 0)
  assert(not plateText(ns, "nameplate2") and not plateText(ns, "nameplate3"))
end)

test("a hit seen at the same moment by target, focus and nameplate: every frame picks the same count", function()
  local ns = fresh({ db = { limit = 0, focus = true }, setup = function(m) m.secretGuid = true end })
  local b = mob("boss")
  M.showPlate(1, b)
  M.target, M.hp = b, 1 M.fire("PLAYER_TARGET_CHANGED")
  M.focus = b M.fire("PLAYER_FOCUS_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 8 do b.hp = b.hp - 0.05 M.hp = b.hp M.hit(b) M.tick(1, 0) end
  M.tick(0.4, 0)
  local t1, t2, t3 = ns.views[1].track, ns.views[2].track, ns.plateViews.nameplate1.track
  assert(t1 == t2 and t2 == t3, "one track")
end)

test("nameplates with their own settings", function()
  local ns = fresh({ db = { limit = 0 } })
  assert(ns.db.plateSame == false and ns.db.p.scale == 0.6 and ns.db.p.limit == 30 and ns.db.p.urgent == 5
    and ns.db.p.icon == false, "own settings by default: small, no icon, from 30 s, red from 5 s")
  local b = mob("x") M.showPlate(1, b)
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 6 do b.hp = b.hp - 0.012 M.hit(b) M.tick(1, 0) end
  M.tick(0.4, 0)
  assert(not plateText(ns, "nameplate1"), "own rule 30 s: hidden at about 80 s")
  assert(ns.plateViews.nameplate1.cells[1].frame:GetScale() == 0.6)
  ns.db.plateSame = true ns.Apply()
  b.hp = b.hp - 0.03 M.hit(b) M.tick(0.4, 0)               -- about 65 s left
  assert(plateText(ns, "nameplate1"), "the target's rule (always): shown")
end)

test("settings: the nameplates column greys out while it follows the target or is off", function()
  local ns = fresh()
  ns.ToggleOptions()
  local w = ns.optionsWindow.widgets
  local function anyEnabled()
    for _, x in ipairs(w.plateRows) do
      if (x.kind == "Button" or x.kind == "CheckButton") and x:IsEnabled() then return true end
    end
  end
  assert(w.allPlates:IsEnabled() and anyEnabled(), "own settings by default: rows usable")
  w.plateSame.checked = true w.plateSame.scripts.OnClick(w.plateSame)
  assert(not anyEnabled(), "same as the target: rows greyed")
  w.plates.checked = false w.plates.scripts.OnClick(w.plates)
  assert(not w.allPlates:IsEnabled() and not w.plateSame:IsEnabled() and not anyEnabled(), "not following: all greyed")
end)

test("the game keeps 'same unit' to itself: target and its nameplate still show one number", function()
  local ns = fresh({ db = { limit = 0, plateSame = true }, setup = function(m) m.secretGuid = true m.secretSame = true end })
  local b, x = mob("boss"), mob("other")
  M.showPlate(1, x) M.showPlate(2, b)
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 4 do b.hp = b.hp - 0.03 M.hit(b) M.tick(1, 0) end   -- counted by its nameplate first
  M.target, M.hp = b, b.hp M.fire("PLAYER_TARGET_CHANGED")
  for _ = 1, 4 do b.hp = b.hp - 0.03 M.hp = b.hp M.hit(b) M.tick(1, 0) end
  M.tick(0.4, 0)
  local function num(t) return t and tonumber(t:match("%d+")) end
  assert(ns.views[1].track == ns.plateViews.nameplate2.track, "one count")
  assert(seconds(ns) and seconds(ns) == num(plateText(ns, "nameplate2")), "the same number")
end)

test("the target's nameplate goes away and comes back: its count goes on, no jump", function()
  local ns = fresh({ db = { limit = 0 }, setup = function(m) m.secretGuid = true end })
  local b = mob("boss")
  M.showPlate(1, b)
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 6 do b.hp = b.hp - 0.02 M.hit(b) M.tick(1, 0) end     -- its nameplate counts first
  M.target, M.hp = b, b.hp M.fire("PLAYER_TARGET_CHANGED")
  for _ = 1, 4 do b.hp = b.hp - 0.02 M.hp = b.hp M.hit(b) M.tick(1, 0) end
  M.tick(0.2, 0)
  local before = seconds(ns)
  local kept = ns.views[1].track
  M.hidePlate(1)                                                   -- the camera turned away
  for _ = 1, 3 do b.hp = b.hp - 0.02 M.hp = b.hp M.hit(b) M.tick(1, 0) end
  M.tick(0.2, 0)
  assert(ns.views[1].track == kept, "the same count without the nameplate")
  near(seconds(ns), before - 3, 3, "no jump")
  M.showPlate(1, b)
  b.hp = b.hp - 0.02 M.hp = b.hp M.hit(b) M.tick(0.4, 0)
  assert(ns.views[1].track == kept and ns.plateViews.nameplate1.track == kept, "the nameplate takes the kept count")
  -- a new target: the kept count is let go
  M.target = mob("new") M.hp = 1 M.fire("PLAYER_TARGET_CHANGED")
  M.tick(0.2, 0)
end)

test("an enemy that resets (evade) starts its count anew", function()
  local ns = fresh({ db = { limit = 0 } })
  fight(8, 0.03)
  assert(shown(ns))
  M.target.evaded = true M.hp = 1
  M.tick(4, 0)                                                     -- no hits, out of combat
  assert(not shown(ns), "nothing after the reset")
  M.target.evaded = nil
  for _ = 1, 2 do M.hp = M.hp - 0.03 M.hit() M.tick(1, 0) end
  assert(not shown(ns), "a new count waits again")
end)

test("group: other enemies need 8 % lost before a number", function()
  local ns = fresh({ db = { limit = 0 }, setup = function(m) m.group = 5 end })
  M.target = mob("trash") M.target.class = "normal" M.hp = 1 M.fire("PLAYER_TARGET_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 6 do M.hp = M.hp - 0.01 M.hit() M.tick(1, 0) end     -- 94 %
  assert(not shown(ns), "6 % lost: not yet")
  for _ = 1, 4 do M.hp = M.hp - 0.01 M.hit() M.tick(1, 0) end     -- 90 %
  assert(shown(ns), "10 % lost: shown")
end)

test("nameplates: frames are reused, never more than 20; dead and idle enemies show nothing", function()
  local ns = fresh({ db = { limit = 0, plateSame = true } })
  assert(ns.PlateViewsBuilt() == 8, "a few made before the fight")
  local ms = {}
  for i = 1, 20 do ms[i] = mob("m" .. i) M.showPlate(i, ms[i]) end
  for _ = 1, 3 do
    for i = 1, 20 do M.hidePlate(i) end
    for i = 1, 20 do M.showPlate(i, ms[i]) end
  end
  assert(ns.PlateViewsBuilt() == 20, "reused: " .. ns.PlateViewsBuilt())
  for i = 21, 25 do M.showPlate(i, mob("m" .. i)) end
  assert(ns.PlateViewsBuilt() == 20 and not ns.plateViews.nameplate21, "never more than 20")
  local a, d = ms[1], ms[2]
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 8 do
    a.hp = a.hp - 0.03 M.hit(a) d.hp = d.hp - 0.03 M.hit(d) M.tick(1, 0)
  end
  M.tick(2, 0)
  assert(plateText(ns, "nameplate1") and plateText(ns, "nameplate2"), "both shown")
  d.dead = true M.tick(0.2, 0)
  assert(not plateText(ns, "nameplate2"), "dead: hidden at once")
  M.tick(4, 0)
  assert(not plateText(ns, "nameplate1"), "no hit for a while: hidden")
end)

test("nameplates: the seconds stand at the chosen height above the nameplate", function()
  local ns = fresh({ db = { plateY = 20 } })
  M.showPlate(1, mob("x"))
  local v = ns.plateViews.nameplate1
  ns.Apply()
  local p = v.hud.point
  assert(p and p[1] == "BOTTOM" and p[3] == "TOP" and math.abs(p[5] * ns.db.p.scale - 20) < 1e-6, "20 above")
end)

test("nameplates: the seconds stand above, right or left of the nameplate, moved by both offsets", function()
  local ns = fresh({ db = { plateAt = "RIGHT", plateX = 10, plateY = -4 } })
  M.showPlate(1, mob("x"))
  local v = ns.plateViews.nameplate1
  ns.Apply()
  local s = ns.db.p.scale
  local p = v.hud.point
  assert(p[1] == "LEFT" and p[3] == "RIGHT", "right of the nameplate")
  assert(math.abs(p[4] * s - 10) < 1e-6 and math.abs(p[5] * s + 4) < 1e-6, "moved 10 right, 4 down")
  ns.db.plateAt = "LEFT" ns.Apply()
  p = v.hud.point
  assert(p[1] == "RIGHT" and p[3] == "LEFT", "left of the nameplate")
  ns.db.plateAt = "TOP" ns.Apply()
  p = v.hud.point
  assert(p[1] == "BOTTOM" and p[3] == "TOP", "above the nameplate")
  -- the settings window: every place in turn, both offsets to their ends
  ns.ToggleOptions()
  local w = ns.optionsWindow.widgets
  local seen = {}
  for _ = 1, 3 do seen[ns.db.plateAt] = true w.plateAt.plus.scripts.OnClick(w.plateAt.plus) end
  assert(seen.TOP and seen.RIGHT and seen.LEFT, "three places")
  for _ = 1, 80 do w.plateX.plus.scripts.OnClick(w.plateX.plus) end
  assert(ns.db.plateX == 100 and not w.plateX.plus:IsEnabled(), "right up to 100")
  for _ = 1, 120 do w.plateX.minus.scripts.OnClick(w.plateX.minus) end
  assert(ns.db.plateX == -100, "left down to -100")
  for _ = 1, 80 do w.plateY.minus.scripts.OnClick(w.plateY.minus) end
  assert(ns.db.plateY == -60 and not w.plateY.minus:IsEnabled(), "down to -60")
end)

test("nameplates: a broken saved place or offset goes back to the default", function()
  local ns = fresh({ db = { plateAt = "MIDDLE", plateX = 500, plateY = -61 } })
  assert(ns.db.plateAt == "TOP" and ns.db.plateX == 0 and ns.db.plateY == 6)
  ns = fresh({ db = { plateAt = "LEFT", plateX = -100, plateY = 60 } })
  assert(ns.db.plateAt == "LEFT" and ns.db.plateX == -100 and ns.db.plateY == 60, "the ends are kept")
end)

test("a big pull never stalls a frame: the work is spread over frames, a cycle every 0.4 s", function()
  local ns = fresh({ db = { limit = 0, plateSame = true }, cycle = true })
  local ms = 0
  debugprofilestop = function() return ms end
  local real = UnitHealthPercent
  UnitHealthPercent = function(...) ms = ms + 0.05 return real(...) end -- each answer costs time
  local ms_ = {}
  for i = 1, 8 do ms_[i] = mob("m" .. i) M.showPlate(i, ms_[i]) end
  M.target, M.hp = ms_[1], 1 M.fire("PLAYER_TARGET_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _, m in ipairs(ms_) do m.fighting = true end
  local worst, frames = 0, 0
  local function frame()
    M.now = M.now + 0.02
    local before = ms
    M.ev.scripts.OnUpdate(M.ev, 0.02)
    if ms - before > worst then worst = ms - before end
    frames = frames + 1
  end
  for _ = 1, 10 do
    for _, m in ipairs(ms_) do m.hp = m.hp - 0.03 M.hit(m) end
    M.hp = ms_[1].hp
    for _ = 1, 50 do frame() end
  end
  assert(worst < 3, "the most one frame took: " .. worst)
  assert(shown(ns), "the target's seconds show")
  UnitHealthPercent, debugprofilestop = real, nil
end)

test("nameplates: 'Show from' only 30 s, 1 min or 1:30; old saved values are moved into it", function()
  local ns = fresh({ db = { p = { limit = 0, scale = 0.7, icon = true, urgent = 30, elite = false } } })
  assert(ns.db.p.limit == 30, "Always is no choice for the nameplates")
  ns.ToggleOptions()
  local lim
  for _, x in ipairs(ns.optionsWindow.widgets.plateRows) do
    if x.tipText == ns.L.tipPlateLimit and x.kind == "Button" and not lim then lim = x end
  end
  assert(lim, "the nameplates' own tooltip")
end)

test("settings show times as 30 s, 1 min, 1:30, 5 min", function()
  local ns = fresh({ db = { limit = 300, urgent = 60 } })
  local want = { [10] = "10 s", [30] = "30 s", [60] = "1 min", [90] = "1:30", [120] = "2 min",
    [300] = "5 min", [600] = "10 min" }
  for v, s in pairs(want) do assert(ns.Dur(v) == s, v .. " -> " .. ns.Dur(v)) end
  ns.ToggleOptions()
  local seen = {}
  for _, f in ipairs(M.frames) do
    if f.kind == "FontString" and f.GetText and f:GetText() then seen[M.reveal(f:GetText())] = true end
  end
  assert(seen["5 min"] and seen["1 min"], "the window shows 5 min and 1 min")
  assert(not seen["300 s"] and not seen["60 s"], "no 300 s / 60 s left")
end)

test("a count that ends while its seconds are still being worked out: no warning, nothing wrong shown", function()
  local ns = fresh({ db = { limit = 0, plateSame = true, focus = true }, cycle = true })
  local ms = 0
  debugprofilestop = function() return ms end
  local real = UnitHealthPercent
  UnitHealthPercent = function(...) ms = ms + 0.4 return real(...) end -- slow: a cycle takes many frames
  local a, b = mob("a"), mob("b")
  M.showPlate(1, a) M.showPlate(2, b)
  M.target, M.hp = a, 1 M.fire("PLAYER_TARGET_CHANGED")
  M.focus = b M.fire("PLAYER_FOCUS_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  a.fighting, b.fighting = true, true
  local function frame() M.now = M.now + 0.02 M.ev.scripts.OnUpdate(M.ev, 0.02) end
  for _ = 1, 8 do
    a.hp = a.hp - 0.04 M.hp = a.hp M.hit(a) b.hp = b.hp - 0.04 M.hit(b)
    for _ = 1, 50 do frame() end
  end
  -- the fight ends in the middle of a cycle: every count is let go, the cycle must not trip on them
  for _ = 1, 12 do frame() end
  a.fighting, b.fighting = false, false
  M.combat = false M.fire("PLAYER_REGEN_ENABLED")
  for _ = 1, 60 do frame() end
  -- and a new target in the middle of a cycle
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  for _ = 1, 6 do a.hp = a.hp - 0.04 M.hp = a.hp M.hit(a) for _ = 1, 50 do frame() end end
  for _ = 1, 7 do frame() end
  M.target = mob("c") M.hp = 1 M.fire("PLAYER_TARGET_CHANGED")
  M.plates[1] = nil M.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
  for _ = 1, 60 do frame() end
  ns.CheckLine("x")
  assert(not ns.db.checks[#ns.db.checks]:find("err%["), ns.db.checks[#ns.db.checks])
  for _, line in ipairs(M.chat) do assert(not line:find(ns.L.warnBroken, 1, true), "warned: " .. line) end
  UnitHealthPercent, debugprofilestop = real, nil
end)

local function settingsOf(db)
  local t = {}
  for _, k in ipairs({ "scale", "icon", "limit", "urgent", "elite", "focus", "focusSame", "plates",
                       "allPlates", "plateSame", "plateAt", "plateY", "plateX", "language" }) do t[k] = tostring(db[k]) end
  for _, g in ipairs({ "f", "p" }) do
    for _, k in ipairs({ "scale", "icon", "limit", "urgent", "elite" }) do t[g .. k] = tostring(db[g][k]) end
  end
  return t
end
local function sameSettings(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false, k .. ": " .. v .. " -> " .. tostring(b[k]) end end
  return true
end
local function chatHas(text)
  for _, l in ipairs(M.chat) do if l:find(text, 1, true) then return l end end
end
-- a fight going on, so every setting meets real seconds on the target, focus and a nameplate
local function selfTestFight(ns)
  local b = mob("boss")
  M.showPlate(1, b)
  M.target, M.hp = b, 1 M.fire("PLAYER_TARGET_CHANGED")
  M.focus = b M.fire("PLAYER_FOCUS_CHANGED")
  M.combat = true M.fire("PLAYER_REGEN_DISABLED")
  b.fighting = true
  for _ = 1, 6 do b.hp = b.hp - 0.01 M.hp = b.hp M.hit(b) M.tick(1, 0) end
  return b
end

test("/lbf selftest: every setting in turn, no errors, the player's settings come back", function()
  local ns = fresh({ db = { scale = 1.3, limit = 120, urgent = 15, focus = true, language = "deDE" } })
  local before = settingsOf(ns.db)
  local b = selfTestFight(ns)
  SlashCmdList.LASTBREATHFOREVER("selftest")
  assert(ns.db.selftestBackup, "kept aside")
  for _ = 1, 60 do b.hp = math.max(0.05, b.hp - 0.004) M.hp = b.hp M.hit(b) M.tick(1, 0) end
  local done = chatHas("self-test done")
  assert(done and done:find("No errors", 1, true) and done:find("in combat", 1, true), tostring(done))
  local n = tonumber(done:match("(%d+) of %d+ settings"))
  assert(n and n > 60, "steps: " .. tostring(n))
  assert(ns.db.selftestBackup == nil)
  assert(sameSettings(before, settingsOf(ns.db)))
  assert(ns.lang == "deDE", "the language is back")
end)

test("/lbf selftest: an error is found and named after the setting it came from", function()
  local ns = fresh({ db = { limit = 300 } })
  local b = selfTestFight(ns)
  local real = UnitHealthPercent
  UnitHealthPercent = function(...) if ns.db.limit == 600 then error("boom") end return real(...) end
  local apply = ns.Apply
  ns.Apply = function(...) if ns.db.p.scale == 3 then error("bang") end return apply(...) end
  SlashCmdList.LASTBREATHFOREVER("selftest")
  for _ = 1, 60 do b.hp = math.max(0.05, b.hp - 0.004) M.hp = b.hp M.hit(b) M.tick(1, 0) end
  UnitHealthPercent, ns.Apply = real, apply
  assert(chatHas("self-test done"))
  -- the game refusing an answer is named too (here: the seconds of the target with "10 min")
  assert(chatHas("target.limit=600: "), "the update error, named: " .. table.concat(M.chat, " | "):sub(-600))
  assert(chatHas("plates.scale=3: ") and chatHas("plates.scale=3: "):find("bang"), "the settings error, named")
  assert(not chatHas(ns.L.warnBroken), "no warning in the chat meanwhile")
  assert(ns.db.limit == 300)
end)

test("/lbf selftest cut off by a reload: the settings come back at the next login; stop works", function()
  local ns = fresh({ db = { scale = 1.4, urgent = 20 } })
  local before = settingsOf(ns.db)
  SlashCmdList.LASTBREATHFOREVER("selftest")
  M.tick(3, 0)
  assert(not sameSettings(before, settingsOf(ns.db)) or ns.db.selftestBackup, "in the middle")
  local saved = LastBreathForeverDB
  ns = fresh({ db = saved })
  assert(chatHas("self-test was cut off"))
  assert(ns.db.selftestBackup == nil and sameSettings(before, settingsOf(ns.db)))
  SlashCmdList.LASTBREATHFOREVER("selftest")
  M.tick(4, 0)
  SlashCmdList.LASTBREATHFOREVER("selftest stop")
  assert(chatHas("self-test stopped"))
  assert(ns.db.selftestBackup == nil and sameSettings(before, settingsOf(ns.db)))
end)

test("/lbf selftest covers every setting: a new setting needs its steps (or a reason to skip it)", function()
  local ns = fresh()
  local keys = {}
  for _, k in ipairs(ns.SELFTEST_KEYS) do keys[k] = true end
  for k in pairs(ns.DEFAULTS) do
    assert(keys[k] or ns.SELFTEST_SKIP[k], "setting '" .. k .. "' is not in /lbf selftest: add steps for it")
  end
  for _, k in ipairs(ns.LOOK) do assert(keys[k], "look '" .. k .. "' is not in /lbf selftest") end
  local names = {}
  for _, st in ipairs(ns.SelfTestSteps()) do names[#names + 1] = st.name end
  local all = table.concat(names, "\n")
  for _, k in ipairs(ns.SELFTEST_KEYS) do
    assert(all:find(k, 1, true), "no step changes '" .. k .. "'")
  end
  for _, prefix in ipairs({ "target.", "focus.", "plates." }) do
    for _, k in ipairs(ns.LOOK) do assert(all:find(prefix .. k, 1, true), "no step for " .. prefix .. k) end
  end
end)

for _, t in ipairs(tests) do
  local c0 = os.clock() local ok, err = pcall(t.fn) if os.getenv("TIMES") then io.write(string.format("%6.2f ", os.clock() - c0)) end
  if ok then io.write("ok   ", t.name, "\n") else failed = failed + 1 io.write("FAIL ", t.name, "\n     ", tostring(err), "\n") end
end
io.write(string.format("\n%d tests, %d failed\n", #tests, failed))
os.exit(failed == 0 and 0 or 1)
