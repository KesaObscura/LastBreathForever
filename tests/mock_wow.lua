-- Minimal World of Warcraft: Forever mock for headless tests (Lua 5.1).
-- The target's health is SECRET: a secret may be stored, formatted and handed to widgets;
-- comparing (<, >), arithmetic and concatenation raise, so a test fails when the addon tries.
-- Limit: `==` between a secret and a number does not raise in Lua 5.1 (different types).
local M = {}
local SECRET = setmetatable({}, { __mode = "k" })
local function raise() error("secret touched", 2) end
function M.secret(v)
  local p = newproxy(true)
  local mt = getmetatable(p)
  mt.__eq, mt.__lt, mt.__le, mt.__concat = raise, raise, raise, raise
  mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__unm = raise, raise, raise, raise, raise
  SECRET[p] = v
  return p
end
function M.reveal(v) if SECRET[v] ~= nil then return SECRET[v] end return v end
function issecretvalue(v) return SECRET[v] ~= nil end
local rawformat = M.rawformat or string.format
M.rawformat = rawformat
string.format = function(fmt, ...)
  local n, a, secret = select("#", ...), { ... }, false
  for i = 1, n do if SECRET[a[i]] ~= nil then a[i] = SECRET[a[i]] secret = true end end
  local s = rawformat(fmt, unpack(a, 1, n))
  return secret and M.secret(s) or s
end

M.now, M.hp, M.combat, M.chat = 100, 1, false, {}
M.target = { exists = true, hostile = true, dead = false, guid = "mob-1", class = "normal", level = 20 }
M.focus, M.bosses = nil, {}   -- other units: mob tables like M.target with their own hp
M.plates = {}          -- [n] = the mob behind "nameplateN"
M.noPlateHits = false  -- the game sends no hits for nameplate units
M.secretGuid = false   -- dungeons: the game does not tell targets apart
M.secretSame = false   -- UnitIsUnit keeps its answer to itself
M.noUnitEvents = {}    -- [unit] = true: the game sends no hits for this unit
M.noCurves = false     -- a client without the curve API
function GetTime() return M.now end
function GetLocale() return M.locale or "enUS" end
function InCombatLockdown() return M.combat end
function date() return "12:00:00" end
M.shots = 0
function Screenshot() M.shots = M.shots + 1 end
local function mob(unit)
  if unit == "target" then return M.target.exists and M.target or nil end
  if unit == "focus" then return M.focus end
  local n = type(unit) == "string" and unit:match("^boss(%d)$")
  if n then return M.bosses[tonumber(n)] end
  local p = type(unit) == "string" and unit:match("^nameplate(%d+)$")
  if p then return M.plates[tonumber(p)] end
  if unit == "player" then return { player = true } end
end
M.mob = mob
-- the target's health is M.hp (the tests move it); other mobs carry their own
local function hpOf(m) if m == M.target then return M.hp end return m.hp or 1 end

local function Curve(step)
  local c = { pts = {}, step = step }
  function c:SetType(t) self.step = (t == 1) end
  function c:ClearPoints() self.pts = {} end
  function c:AddPoint(x, y)
    if SECRET[x] ~= nil or SECRET[y] ~= nil then error("AddPoint: secret") end
    table.insert(self.pts, { x, y })
  end
  function c:Eval(x)
    local p = self.pts
    if x <= p[1][1] then return p[1][2] end
    for i = 2, #p do
      if x < p[i][1] then
        local a, b = p[i - 1], p[i]
        if self.step then return a[2] end
        return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
      end
    end
    return p[#p][2]
  end
  return c
end
C_CurveUtil = {
  CreateCurve = function() if M.noCurves then error("no curves") end return Curve(false) end,
  CreateColorCurve = function() if M.noCurves then error("no curves") end return Curve(true) end,
}
Enum = { LuaCurveType = { Linear = 0, Step = 1 } }
function CreateColor(r, g, b, a)
  return { r = r, g = g, b = b, a = a, GetRGBA = function(s) return s.r, s.g, s.b, M.secret(s.a) end }
end
function UnitHealthPercent(unit, predicted, curve)
  if type(predicted) ~= "boolean" then error("usage: unit, usePredicted, curve") end
  local m = mob(unit)
  if not m then error("no such unit") end
  local v = curve:Eval(hpOf(m))
  if type(v) == "table" then return v end
  return M.secret(v)
end
function UnitExists(u) return mob(u) ~= nil end
function UnitCanAttack(_, u) local m = mob(u) return m ~= nil and m.hostile ~= false end
function UnitIsDeadOrGhost(u) local m = mob(u) return m ~= nil and m.dead == true end
function UnitGUID(u)
  local m = mob(u)
  if not m then return nil end
  if M.secretGuid then return M.secret(m.guid) end
  return m.guid
end
M.noCombatInfo = false -- the game does not say whether a unit is fighting
function UnitAffectingCombat(u)
  local m = mob(u)
  if M.noCombatInfo then return M.secret(true) end
  if m == nil or m.evaded then return false end
  -- a mob that was hit fights while the player fights
  return m.fighting == true or (m.wasHit == true and M.combat == true)
end
M.group = 0
function GetNumGroupMembers() return M.group end
function UnitClassification(u) local m = mob(u) return m and m.class or "normal" end
function UnitLevel(u) local m = mob(u) return m and m.level or 1 end
function UnitIsUnit(a, b)
  local x, y = mob(a), mob(b)
  local r = x ~= nil and x == y
  if M.secretSame then return M.secret(r) end
  return r
end

-- widgets: unknown methods do nothing, the ones the tests look at keep state
local methods = {}
local function noop() end
-- methods start with a capital letter; any other unknown key is a plain missing field (nil)
local W = { __index = function(_, k)
  if methods[k] then return methods[k] end
  if type(k) == "string" and k:match("^%u") then return noop end
end }
M.frames = {}
local function new(kind, parent)
  local o = setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, alpha = 1, enabled = true }, W)
  M.frames[#M.frames + 1] = o
  return o
end
function methods:SetText(t)
  if t ~= nil and type(t) ~= "string" and SECRET[t] == nil then error("SetText wants a string") end
  self.text = t
end
function methods:GetText() return self.text end
function methods:SetAlpha(a) self.alpha = a end
function methods:SetParent(p) self.parent = p end
function methods:SetScript(k, f) self.scripts[k] = f end
function methods:HookScript() end
function methods:GetScript(k) return self.scripts[k] end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(v) self.shown = v and true or false end
function methods:IsShown() return self.shown end
function methods:SetEnabled(v) self.enabled = v and true or false end
function methods:IsEnabled() return self.enabled end
function methods:SetChecked(v) self.checked = v and true or false end
function methods:GetChecked() return self.checked end
function methods:SetScale(s) self.scale = s end
function methods:GetScale() return self.scale or 1 end
function methods:SetWidth(w) self.w = w end
function methods:GetWidth() return self.w or 100 end
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:SetHeight(h) self.h = h end
function methods:GetHeight() return self.h or 0 end
function methods:GetLeft() return M.lt and M.lt[1] end
function methods:GetTop() return M.lt and M.lt[2] end
function methods:GetCenter() return M.center and M.center[1], M.center and M.center[2] end
function methods:SetPoint(...) self.point = { ... } end
function methods:GetFrameLevel() return 1 end
function methods:GetStringWidth() return self.text and #tostring(M.reveal(self.text)) * 6 or 0 end
function methods:CreateFontString() return new("FontString", self) end
function methods:CreateTexture() return new("Texture", self) end
function methods:GetFontString()
  local fs = rawget(self, "fs")
  if not fs then fs = new("FontString", self) rawset(self, "fs", fs) end
  return fs
end
function methods:SetMotionScriptsWhileDisabled(v) self.motionWhileDisabled = v end
function CreateFrame(kind, name, parent, template)
  if template then error("no templates in the mock") end
  local f = new(kind, parent)
  if name then _G[name] = f end
  return f
end
UIParent = new("Frame")
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) M.chat[#M.chat + 1] = m end }
GameTooltip = { lines = {}, SetOwner = function() end, Show = function() end, Hide = function() end,
  SetText = function(self, t) self.lines = { t } end,
  AddLine = function(self, t) self.lines[#self.lines + 1] = t end,
  AddDoubleLine = function(self, a, b) self.lines[#self.lines + 1] = a .. " " .. b end }
SlashCmdList = {}

-- visible on screen: shown and not transparent, all the way up
function M.visible(f)
  while f do
    if not f.shown then return false end
    if M.reveal(f.alpha) == 0 then return false end
    f = f.parent
  end
  return true
end

function M.load(root)
  local ns = {}
  for _, file in ipairs({ "Locale.lua", "Skin.lua", "Core.lua", "Options.lua", "SelfTest.lua" }) do
    assert(loadfile(root .. file))("LastBreathForever", ns)
  end
  for _, f in ipairs(M.frames) do if f.scripts.OnUpdate then M.ev = f end end
  M.ns = ns
  return ns
end
function M.fire(e, ...)
  for i = 1, #M.frames do
    local f = M.frames[i]
    if f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end
  end
end
-- C_Timer.After: run when their time has come, checked at every tick
M.timers = {}
C_Timer = { After = function(d, f) M.timers[#M.timers + 1] = { at = M.now + d, f = f } end }
function M.runTimers()
  local due = {}
  for i = #M.timers, 1, -1 do
    if M.timers[i].at <= M.now + 1e-9 then due[#due + 1] = table.remove(M.timers, i) end
  end
  for i = #due, 1, -1 do due[i].f() end
end
local errorHandler = function(e) error(e, 0) end
function geterrorhandler() return errorHandler end
function seterrorhandler(f) errorHandler = f end
function M.tick(seconds, hpPerSecond)
  local steps = math.floor(seconds / 0.2 + 0.5)
  for _ = 1, steps do
    M.now = M.now + 0.2
    M.hp = math.max(0, M.hp - (hpPerSecond or 0) * 0.2)
    M.ev.scripts.OnUpdate(M.ev, 0.2)
    M.runTimers()
  end
end
-- a hit on a mob (the target when none is given): the game tells every unit name it has
function M.hit(m)
  m = m or M.target
  if m then m.wasHit = true end
  local units = { "target", "focus" }
  for i = 1, 4 do units[#units + 1] = "boss" .. i end
  for i = 1, 20 do units[#units + 1] = "nameplate" .. i end
  for _, u in ipairs(units) do
    local plate = u:find("^nameplate")
    if mob(u) == m and not M.noUnitEvents[u] and not (plate and M.noPlateHits) then
      M.fire("UNIT_COMBAT", u, "WOUND")
    end
  end
end
-- a nameplate comes into view / goes away
M.plateFrames = {}
function M.showPlate(n, m)
  M.plates[n] = m
  M.plateFrames[n] = M.plateFrames[n] or CreateFrame("Frame")
  M.fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. n)
end
function M.hidePlate(n)
  M.fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. n)
  M.plates[n] = nil
end
C_NamePlate = { GetNamePlateForUnit = function(u)
  local m = mob(u)
  for n, x in pairs(M.plates) do if x == m then return M.plateFrames[n] end end
end }

return M
