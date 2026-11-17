-- Last Breath Forever - about how many seconds the current target has left.
-- The target's health is secret for addons: nothing here compares it or calculates with it.
-- The game works the seconds out itself and hands back a value that can only be shown.

local ADDON, ns = ...
ns.VERSION = "0.1.0"
local L = ns.L
local Skin = ns.Skin

local TICK = 0.2
local MIN_HITS = 3         -- hits on the target before an estimate shows
local MIN_TIME = 2         -- seconds since the first hit before an estimate shows
local FULL = 0.90          -- from this share up at the first hit the target counts as full
local STEP = 0.05          -- below that: bands of this width, each with its own estimate
local LOWEST = 0.20        -- a target first hit below this share gets no estimate
local LOST = 0.05          -- a band's estimate shows once the target is this far below the band
local CAP = 3600           -- the longest estimate (seconds)
local SLOTS = 8            -- targets remembered during one fight
ns.LIMITS = { 0, 30, 60, 120, 300, 600 } -- "Show from": 0 = always
ns.URGENTS = { 0, 3, 5, 10, 15, 20, 30, 45, 60 } -- "Last seconds in red": 0 = off
local SECONDS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 25, 30, 35, 40, 50, 60,
  75, 90, 120, 150, 180, 240, 300, 450, 600, 900, 1200, 1800, 2700, 3600 }

local DEFAULTS = {
  locked = true,
  scale = 1,       -- size of the seconds and the icon
  icon = true,
  limit = 300,     -- seconds: show from here down (0 = always)
  urgent = 5,      -- seconds: red from here down (0 = off)
  elite = false,   -- only elite, rare and boss targets
}
ns.DEFAULTS = DEFAULTS

local db
local function Print(fmt, ...)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd650f0Last Breath Forever|r " .. string.format(fmt, ...))
end
ns.Print = Print

------------------------------------------------------------------------
-- safe reads
------------------------------------------------------------------------
local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

-- a plain boolean, or nil when the game keeps the answer to itself
local function Bool(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if not ok or IsSecret(v) or type(v) ~= "boolean" then return nil end
  return v
end

-- a plain string or number, else nil
local function Plain(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if not ok or IsSecret(v) then return nil end
  local t = type(v)
  if t ~= "string" and t ~= "number" then return nil end
  return v
end

local warned
local function Broken()
  if not warned then
    warned = true
    Print("%s", L.warnBroken)
  end
end

------------------------------------------------------------------------
-- settings
------------------------------------------------------------------------
local function InList(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function InitDB()
  if type(LastBreathForeverDB) ~= "table" then LastBreathForeverDB = {} end
  db = LastBreathForeverDB
  for k, v in pairs(DEFAULTS) do
    if type(db[k]) ~= type(v) then db[k] = v end
  end
  if db.scale < 0.5 or db.scale > 3 then db.scale = DEFAULTS.scale end
  if not InList(ns.LIMITS, db.limit) then db.limit = DEFAULTS.limit end
  if not InList(ns.URGENTS, db.urgent) then db.urgent = DEFAULTS.urgent end
  if db.point ~= nil and (type(db.point) ~= "table" or type(db.point[1]) ~= "number"
      or type(db.point[2]) ~= "number") then db.point = nil end
  ns.db = db
end

------------------------------------------------------------------------
-- the frame on screen
------------------------------------------------------------------------
local hud, icon2, sample, unlockBg, lockBtn, setBtn
-- A target may already be hurt when its first hit is seen. The addon cannot read how much, so
-- the health scale is cut into bands: BANDS[k] = { lo, hi, start } (start = the share the
-- estimate of that band counts from). Every band has its own seconds on screen; the game shows
-- the one whose band the target was in at its first hit, and nothing else.
local BANDS = { { lo = FULL, hi = 1.01, start = 1 } }
do
  local hi = FULL
  while hi - STEP >= LOWEST - 0.001 do
    BANDS[#BANDS + 1] = { lo = hi - STEP, hi = hi, start = hi - STEP / 2 }
    hi = hi - STEP
  end
end
ns.BANDS = BANDS
local slots = {}   -- [i] = { frame, gates[k], guid, hit, lastHit, hits, used }
local cells = {}   -- [k] = { frame, icon, textN, textU }: the seconds of band k
local cur          -- the slot of the current target, or nil
local inCombat = false

-- text with letters ("s", "с", "초"): only the game's own font objects keep every alphabet
local function BigFont(fs)
  for _, name in ipairs({ "GameFontNormalHugeOutline", "GameFontNormalLargeOutline",
                          "GameFontHighlightOutline", "GameFontHighlightLarge" }) do
    if _G[name] then fs:SetFontObject(name) return end
  end
end

local function PlaceHud()
  hud:SetScale(db.scale)
  hud:ClearAllPoints()
  if db.point then
    -- the point is kept in screen units, so a new size leaves the frame where it is
    hud:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.point[1] / db.scale, db.point[2] / db.scale)
  else
    hud:SetPoint("CENTER", UIParent, "CENTER", 0, 140 / db.scale)
  end
end

local function HudButton(text, tipTitle, tipText)
  local b = CreateFrame("Button", nil, hud)
  b:SetSize(80, 20)
  Skin.RedButton(b)
  b:SetNormalFontObject("GameFontNormalSmall")
  b:SetHighlightFontObject("GameFontHighlightSmall")
  b:SetText(text)
  local fs = b:GetFontString()
  if fs and fs.GetStringWidth then b:SetWidth(math.max(80, math.ceil(fs:GetStringWidth() or 0) + 20)) end
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tipTitle, 1, 1, 1)
    GameTooltip:AddLine(tipText, 0.82, 0.82, 0.82, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function ApplyLock()
  local unlocked = not db.locked
  hud:EnableMouse(unlocked)
  unlockBg:SetShown(unlocked)
  hud.edge:SetShown(unlocked)
  sample:SetShown(unlocked)
  hud.drag:SetShown(unlocked)
  lockBtn:SetShown(unlocked)
  setBtn:SetShown(unlocked)
end

local function ApplyLook()
  PlaceHud()
  icon2:SetShown(db.icon and not db.locked)
  sample:ClearAllPoints()
  -- with the icon the seconds stand right of it, without it they are centred
  local point, x = "CENTER", 0
  if db.icon then point, x = "LEFT", 34 end
  sample:SetPoint(point, hud, point, x, 0)
  for _, c in ipairs(cells) do
    c.icon:SetShown(db.icon)
    c.textN:ClearAllPoints()
    c.textN:SetPoint(point, hud, point, x, 0)
    c.textU:ClearAllPoints()
    c.textU:SetAllPoints(c.textN)
  end
  sample:SetText(string.format(L.fmtSec, 12))
end

function ns.SetLocked(locked, quiet)
  db.locked = locked and true or false
  ApplyLock()
  ApplyLook()
  if not quiet then Print("%s", db.locked and L.msgLocked or L.msgUnlocked) end
  if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.ResetPosition()
  db.point = nil
  PlaceHud()
  Print("%s", L.msgReset)
end

function ns.Apply()
  ApplyLock()
  ApplyLook()
end

local function BuildHud()
  hud = CreateFrame("Frame", "LastBreathForeverFrame", UIParent)
  hud:SetSize(130, 30)
  hud:SetMovable(true)
  hud:SetClampedToScreen(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    if x and y then
      db.point = { x * db.scale, y * db.scale }
      PlaceHud()
    end
  end)

  -- while unlocked: a dark plate in the addon's colour, a sample and two buttons
  unlockBg = hud:CreateTexture(nil, "BACKGROUND")
  unlockBg:SetAllPoints()
  unlockBg:SetColorTexture(Skin.BG[1], Skin.BG[2], Skin.BG[3], 0.85)
  hud.edge = CreateFrame("Frame", nil, hud)
  hud.edge:SetAllPoints()
  Skin.Edge(hud.edge, Skin.ACCENT, 0.9)
  hud.drag = hud:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hud.drag:SetPoint("BOTTOM", hud, "TOP", 0, 3)
  hud.drag:SetText(L.hudDrag)
  sample = hud:CreateFontString(nil, "OVERLAY")
  BigFont(sample)
  icon2 = hud:CreateTexture(nil, "ARTWORK")
  icon2:SetSize(26, 26)
  icon2:SetPoint("LEFT", hud, "LEFT", 3, 0)
  icon2:SetTexture(Skin.LOGO)
  lockBtn = HudButton(L.optLock, L.optLock, L.tipHudLock)
  lockBtn:SetPoint("TOPRIGHT", hud, "BOTTOM", -2, -4)
  lockBtn:SetScript("OnClick", function() ns.SetLocked(true) end)
  setBtn = HudButton(L.hudSettings, L.hudSettings, L.tipHudSettings)
  setBtn:SetPoint("TOPLEFT", hud, "BOTTOM", 2, -4)
  setBtn:SetScript("OnClick", function() if ns.ToggleOptions then ns.ToggleOptions(true) end end)

  -- one frame per remembered target, with one inner frame per band. The game sets the
  -- opacity of the inner frames once, at the first hit: visible for the band the target was
  -- in, invisible for all others.
  for i = 1, SLOTS do
    local f = CreateFrame("Frame", nil, hud)
    f:SetAllPoints()
    local gates = {}
    for k = 1, #BANDS do
      gates[k] = CreateFrame("Frame", nil, f)
      gates[k]:SetAllPoints(hud)
      gates[k]:SetAlpha(0)
    end
    slots[i] = { frame = f, gates = gates, hits = 0, used = 0 }
  end
  -- the seconds of each band; the opacity of a cell follows "Show from", set anew by the
  -- game on every update. The cells sit in the inner frames of the current target.
  for k = 1, #BANDS do
    local c = {}
    c.frame = CreateFrame("Frame", nil, slots[1].gates[k])
    c.frame:SetAllPoints(hud)
    c.icon = c.frame:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(26, 26)
    c.icon:SetPoint("LEFT", hud, "LEFT", 3, 0)
    c.icon:SetTexture(Skin.LOGO)
    c.textN = c.frame:CreateFontString(nil, "OVERLAY")
    BigFont(c.textN)
    c.textN:SetTextColor(1, 1, 1)
    c.textU = c.frame:CreateFontString(nil, "OVERLAY")
    BigFont(c.textU)
    c.textU:SetTextColor(1, 0.25, 0.30)
    c.textU:SetAlpha(0)
    c.frame:Hide()
    cells[k] = c
  end
  ns.hud, ns.cells, ns.slots = hud, cells, slots
end

------------------------------------------------------------------------
-- what the game is asked
------------------------------------------------------------------------
local ttdCurve, limitCurve, urgentCurve, normalCurve
local bandCurves = {} -- [k]: yes while the health is inside band k
local ON, OFF -- the two colours of the yes / no curves, made once

local function NewCurve(colour)
  local make = C_CurveUtil and (colour and C_CurveUtil.CreateColorCurve or C_CurveUtil.CreateCurve)
  if not make then return nil end
  local ok, c = pcall(make)
  if not ok or not c then return nil end
  pcall(c.SetType, c, colour and Enum.LuaCurveType.Step or Enum.LuaCurveType.Linear)
  return c
end

local function InitCurves()
  ttdCurve = NewCurve(false)
  limitCurve, urgentCurve, normalCurve = NewCurve(true), NewCurve(true), NewCurve(true)
  if not (ttdCurve and limitCurve and urgentCurve and normalCurve and CreateColor) then return false end
  ON, OFF = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0)
  for k, b in ipairs(BANDS) do
    local c = NewCurve(true)
    if not c then return false end
    c:AddPoint(0, OFF)
    c:AddPoint(b.lo, ON)
    if b.hi <= 1 then c:AddPoint(b.hi, OFF) end
    bandCurves[k] = c
  end
  return true
end

-- the share of health at which the target has `seconds` left, when it has been losing health
-- evenly for T seconds since it was at `start`: the same rule the seconds themselves follow
local function ShareAt(seconds, T, start) return seconds * start / (seconds + T) end

-- yes below the share, no above it (yesBelow) or the other way round
local function Band(curve, share, yesBelow)
  curve:ClearPoints()
  curve:AddPoint(0, yesBelow and ON or OFF)
  curve:AddPoint(math.min(share, 1), yesBelow and OFF or ON)
end

local function Percent(curve) return pcall(UnitHealthPercent, "target", false, curve) end

-- the game's yes / no as the opacity of a frame or text; false when that did not work
local function Opacity(region, curve)
  local ok, colour = Percent(curve)
  if not ok or type(colour) ~= "table" then return false end
  local okA, _, _, _, a = pcall(colour.GetRGBA, colour)
  return okA and (pcall(region.SetAlpha, region, a)) or false
end

------------------------------------------------------------------------
-- targets
------------------------------------------------------------------------
local function Hostile()
  return Bool(UnitExists, "target") == true and Bool(UnitCanAttack, "player", "target") == true
    and Bool(UnitIsDeadOrGhost, "target") == false
end

local STRONG = { elite = true, rareelite = true, rare = true, worldboss = true }
local function Wanted()
  if not db.elite then return true end
  if STRONG[Plain(UnitClassification, "target") or ""] then return true end
  return Plain(UnitLevel, "target") == -1
end

local useCount = 0
local function FreeSlot()
  local best
  for _, s in ipairs(slots) do
    if not best or s.used < best.used then best = s end
  end
  best.guid, best.hit, best.lastHit, best.hits = nil, nil, nil, 0
  for _, g in ipairs(best.gates) do g:SetAlpha(0) end
  return best
end

local function HideCells()
  for _, c in ipairs(cells) do c.frame:Hide() end
end

local function Select(slot)
  cur = slot
  if slot then
    useCount = useCount + 1
    slot.used = useCount
    for k, c in ipairs(cells) do
      c.frame:SetParent(slot.gates[k])
      c.frame:SetAllPoints(hud)
    end
  end
  HideCells()
end

local function ForgetAll()
  for _, s in ipairs(slots) do
    s.guid, s.hit, s.lastHit, s.hits, s.used = nil, nil, nil, 0, 0
    for _, g in ipairs(s.gates) do g:SetAlpha(0) end
  end
  useCount = 0
  Select(nil)
end

local function TargetChanged()
  if not Hostile() then Select(nil) return end
  -- where the game tells targets apart, a target met again in the same fight keeps its count
  local guid = Plain(UnitGUID, "target")
  if type(guid) == "string" then
    for _, s in ipairs(slots) do
      if s.guid == guid then Select(s) return end
    end
  end
  local s = FreeSlot()
  s.guid = type(guid) == "string" and guid or nil
  Select(s)
end

local function TargetHit()
  if not cur then return end
  local now = GetTime()
  cur.hits = cur.hits + 1
  cur.lastHit = now
  if not cur.hit then
    cur.hit = now
    -- the game marks, once, the band this target is in now; all other bands stay invisible
    for k, g in ipairs(cur.gates) do
      if not Opacity(g, bandCurves[k]) then
        for _, x in ipairs(cur.gates) do x:SetAlpha(0) end
        Broken()
        break
      end
    end
  end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
local function Ready()
  if not cur or not cur.hit or cur.hits < MIN_HITS then return false end
  if GetTime() - cur.hit < MIN_TIME then return false end
  if Bool(UnitIsDeadOrGhost, "target") ~= false then return false end
  return Wanted()
end

-- the seconds of one band: text, "Show from", red or white
local function ShowBand(k, T)
  local b, c = BANDS[k], cells[k]
  ttdCurve:ClearPoints()
  ttdCurve:AddPoint(0, 0)
  for i = 1, #SECONDS do
    local s = SECONDS[i]
    ttdCurve:AddPoint(ShareAt(s, T, b.start), s)
  end
  ttdCurve:AddPoint(1, CAP)
  local ok, seconds = Percent(ttdCurve)
  if not ok then return false end
  local okT, text = pcall(string.format, L.fmtSec, seconds)
  if not okT then return false end
  c.textN:SetText(text)
  c.textU:SetText(text)
  -- "Show from": hidden while more than the limit is left, and until the target has lost
  -- enough for an estimate (a full target: next to nothing; a hurt one: LOST below its band)
  local limit = db.limit > 0 and db.limit or CAP
  local top = k == 1 and 0.995 or (b.lo - LOST)
  Band(limitCurve, math.min(ShareAt(limit, T, b.start), top), true)
  if not Opacity(c.frame, limitCurve) then return false end
  -- "Last seconds in red": the red text below the mark, the white one above it
  if db.urgent > 0 then
    local share = ShareAt(db.urgent, T, b.start)
    Band(urgentCurve, share, true)
    Band(normalCurve, share, false)
    if not (Opacity(c.textU, urgentCurve) and Opacity(c.textN, normalCurve)) then return false end
  else
    c.textU:SetAlpha(0)
    c.textN:SetAlpha(1)
  end
  return true
end

local function Show()
  -- the first hit already took its share of health but no time: count one average gap
  -- between hits before it
  local start = cur.hit - (cur.lastHit - cur.hit) / (cur.hits - 1)
  local T = GetTime() - start
  for k = 1, #BANDS do
    if not ShowBand(k, T) then return false end
  end
  return true
end

local function Update()
  if not db.locked or not Ready() then HideCells() return end
  if Show() then
    for _, c in ipairs(cells) do c.frame:Show() end
  else
    HideCells()
    Broken()
  end
end
ns.Update = Update

------------------------------------------------------------------------
-- events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local acc = 0
local ready = false
ev:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < TICK then return end
  acc = 0
  if not ready then return end
  -- an error in here hides the seconds: no number is better than a wrong one
  if not pcall(Update) then
    HideCells()
    Broken()
  end
end)

local function OnEvent(_, event, a1, a2)
  if event == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    InitDB()
    BuildHud()
    ready = InitCurves()
    if not ready then Broken() end
    ns.Apply()
    if ns.InitOptions then ns.InitOptions() end
  elseif not ready then
    return
  elseif event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    -- a fight never starts with the frame unlocked under the cursor
    if not db.locked then ns.SetLocked(true, true) end
    if not cur then TargetChanged() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    ForgetAll()
    TargetChanged()
  elseif event == "PLAYER_TARGET_CHANGED" then
    TargetChanged()
  elseif event == "PLAYER_ENTERING_WORLD" then
    inCombat = Bool(InCombatLockdown) == true
    if inCombat and not db.locked then ns.SetLocked(true, true) end
    ForgetAll()
    TargetChanged()
  elseif event == "UNIT_COMBAT" then
    if a1 == "target" and not IsSecret(a2) and a2 == "WOUND" then TargetHit() end
  end
end
ev:SetScript("OnEvent", OnEvent)
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
if not pcall(ev.RegisterUnitEvent, ev, "UNIT_COMBAT", "target") then pcall(ev.RegisterEvent, ev, "UNIT_COMBAT") end

------------------------------------------------------------------------
-- commands and the addon menu at the minimap
------------------------------------------------------------------------
SLASH_LASTBREATHFOREVER1 = "/lbf"
SLASH_LASTBREATHFOREVER2 = "/lastbreath"
SlashCmdList.LASTBREATHFOREVER = function(msg)
  msg = string.lower((msg or ""):match("^%s*(.-)%s*$"))
  if msg == "lock" then
    ns.SetLocked(true)
  elseif msg == "unlock" then
    if inCombat then Print("%s", L.msgLocked) else ns.SetLocked(false) end
  elseif msg == "reset" then
    ns.ResetPosition()
  elseif msg == "help" or msg == "?" then
    for _, k in ipairs({ "help1", "help2", "help3", "help4" }) do Print("%s", L[k]) end
  elseif ns.ToggleOptions then
    ns.ToggleOptions()
  end
end

function LastBreathForever_OnCompartmentClick()
  if ns.ToggleOptions then ns.ToggleOptions() end
end

function LastBreathForever_OnCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
  GameTooltip:AddDoubleLine("Last Breath Forever", "v" .. ns.VERSION, 0.84, 0.31, 0.94, 1, 0.82, 0)
  GameTooltip:AddDoubleLine(L.cmpLeft, L.cmpSettings, 1, 0.82, 0, 1, 1, 1)
  GameTooltip:Show()
end

function LastBreathForever_OnCompartmentLeave()
  GameTooltip:Hide()
end
