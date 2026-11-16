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
local WAS_FULL = 0.90      -- the target must have had at least this share at the first hit
local CAP = 3600           -- the longest estimate (seconds)
local SLOTS = 8            -- targets remembered during one fight
ns.LIMITS = { 0, 30, 60, 120, 300, 600 } -- "Show from": 0 = always
ns.URGENTS = { 0, 3, 5, 10 }             -- "Last seconds in red": 0 = off
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
local hud, live, textN, textU, icon, icon2, sample, unlockBg, lockBtn, setBtn
local slots = {}   -- [i] = { frame, guid, hit, lastHit, hits, used }
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
  live:SetShown(not unlocked) -- the sample stands in for the real seconds while unlocked
end

local function ApplyLook()
  PlaceHud()
  icon:SetShown(db.icon)
  icon2:SetShown(db.icon and not db.locked)
  textN:ClearAllPoints()
  textU:ClearAllPoints()
  sample:ClearAllPoints()
  -- with the icon the seconds stand right of it, without it they are centred
  if db.icon then
    textN:SetPoint("LEFT", hud, "LEFT", 34, 0)
    sample:SetPoint("LEFT", hud, "LEFT", 34, 0)
  else
    textN:SetPoint("CENTER", hud, "CENTER", 0, 0)
    sample:SetPoint("CENTER", hud, "CENTER", 0, 0)
  end
  textU:SetAllPoints(textN)
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

  -- one frame per remembered target. Its opacity is set once, at the first hit, by the game:
  -- visible if the target was (almost) full then. Everything shown for that target sits inside.
  for i = 1, SLOTS do
    local f = CreateFrame("Frame", nil, hud)
    f:SetAllPoints()
    f:SetAlpha(0)
    slots[i] = { frame = f, hits = 0, used = 0 }
  end
  -- the opacity of this one follows "Show from", set anew by the game on every update
  live = CreateFrame("Frame", nil, slots[1].frame)
  live:SetAllPoints(hud)
  icon = live:CreateTexture(nil, "ARTWORK")
  icon:SetSize(26, 26)
  icon:SetPoint("LEFT", hud, "LEFT", 3, 0)
  icon:SetTexture(Skin.LOGO)
  textN = live:CreateFontString(nil, "OVERLAY")
  BigFont(textN)
  textN:SetTextColor(1, 1, 1)
  textU = live:CreateFontString(nil, "OVERLAY")
  BigFont(textU)
  textU:SetTextColor(1, 0.25, 0.30)
  textU:SetAlpha(0)
  live:Hide()
  ns.hud, ns.live, ns.textN, ns.textU, ns.slots = hud, live, textN, textU, slots
end

------------------------------------------------------------------------
-- what the game is asked
------------------------------------------------------------------------
local ttdCurve, limitCurve, urgentCurve, normalCurve, fullCurve
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
  limitCurve, urgentCurve, normalCurve, fullCurve = NewCurve(true), NewCurve(true), NewCurve(true), NewCurve(true)
  if not (ttdCurve and limitCurve and urgentCurve and normalCurve and fullCurve and CreateColor) then return false end
  ON, OFF = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0)
  -- "was (almost) full": yes from WAS_FULL up
  fullCurve:AddPoint(0, OFF)
  fullCurve:AddPoint(WAS_FULL, ON)
  return true
end

-- the share of health at which the target has `seconds` left, when it has been losing health
-- evenly for T seconds since it was full: the same rule the seconds themselves follow
local function ShareAt(seconds, T) return seconds / (seconds + T) end

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
  best.frame:SetAlpha(0)
  return best
end

local function Select(slot)
  cur = slot
  if slot then
    useCount = useCount + 1
    slot.used = useCount
    live:SetParent(slot.frame)
    live:SetAllPoints(hud)
  end
  live:Hide()
end

local function ForgetAll()
  for _, s in ipairs(slots) do
    s.guid, s.hit, s.lastHit, s.hits, s.used = nil, nil, nil, 0, 0
    s.frame:SetAlpha(0)
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
    -- the game decides once whether this target was (almost) full; no: nothing shows for it
    if not Opacity(cur.frame, fullCurve) then
      cur.frame:SetAlpha(0)
      Broken()
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

local function Show()
  -- the first hit already took its share of health but no time: count one average gap
  -- between hits before it
  local start = cur.hit - (cur.lastHit - cur.hit) / (cur.hits - 1)
  local T = GetTime() - start
  ttdCurve:ClearPoints()
  ttdCurve:AddPoint(0, 0)
  for i = 1, #SECONDS do
    local s = SECONDS[i]
    ttdCurve:AddPoint(ShareAt(s, T), s)
  end
  ttdCurve:AddPoint(1, CAP)
  local ok, seconds = Percent(ttdCurve)
  if not ok then return false end
  local okT, text = pcall(string.format, L.fmtSec, seconds)
  if not okT then return false end
  textN:SetText(text)
  textU:SetText(text)
  -- "Show from": hidden while more than the limit is left (and while next to nothing is lost)
  local limit = db.limit > 0 and db.limit or CAP
  Band(limitCurve, math.min(ShareAt(limit, T), 0.995), true)
  if not Opacity(live, limitCurve) then return false end
  -- "Last seconds in red": the red text below the mark, the white one above it
  if db.urgent > 0 then
    local share = ShareAt(db.urgent, T)
    Band(urgentCurve, share, true)
    Band(normalCurve, share, false)
    if not (Opacity(textU, urgentCurve) and Opacity(textN, normalCurve)) then return false end
  else
    textU:SetAlpha(0)
    textN:SetAlpha(1)
  end
  return true
end

local function Update()
  if not db.locked or not Ready() then live:Hide() return end
  if Show() then
    live:Show()
  else
    live:Hide()
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
    live:Hide()
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
