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
local BOSSES = 4           -- bosses of an encounter followed in the background
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
  focus = false,   -- a second frame for the focus
  focusSame = true, -- the focus frame uses the target frame's settings
  shots = false,   -- test builds: screenshots in boss fights (/lbf shots)
  language = "auto", -- "auto" = the game's language, else one of ns.LANGUAGES
}
ns.DEFAULTS = DEFAULTS
ns.LOOK = { "scale", "icon", "limit", "urgent", "elite" } -- what each frame can have of its own

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
  -- the look of a frame: the target's lies in db itself, the focus' own in db.f
  local function look(t)
    for _, k in ipairs(ns.LOOK) do
      if type(t[k]) ~= type(DEFAULTS[k]) then t[k] = DEFAULTS[k] end
    end
    if t.scale < 0.5 or t.scale > 3 then t.scale = DEFAULTS.scale end
    if not InList(ns.LIMITS, t.limit) then t.limit = DEFAULTS.limit end
    if not InList(ns.URGENTS, t.urgent) then t.urgent = DEFAULTS.urgent end
  end
  look(db)
  if type(db.f) ~= "table" then
    db.f = {}
    for _, k in ipairs(ns.LOOK) do db.f[k] = db[k] end
  end
  look(db.f)
  local known = db.language == "auto"
  for _, l in ipairs(ns.LANGUAGES) do if l.code == db.language then known = true end end
  if not known then db.language = "auto" end
  ns.SetLanguage(db.language)
  for _, key in ipairs({ "point", "focusPoint", "optPoint" }) do
    local p = db[key]
    if p ~= nil and (type(p) ~= "table" or type(p[1]) ~= "number" or type(p[2]) ~= "number") then db[key] = nil end
  end
  if type(db.checks) ~= "table" then db.checks = {} end
  ns.db = db
end

------------------------------------------------------------------------
-- bands
------------------------------------------------------------------------
-- A unit may already be hurt when its first hit is seen. The addon cannot read how much, so
-- the health scale is cut into bands: BANDS[k] = { lo, hi, start } (start = the share the
-- estimate of that band counts from). Every band has its own seconds on screen; the game shows
-- the one whose band the unit was in at its first hit, and nothing else.
local BANDS = { { lo = FULL, hi = 1.01, start = 1 } }
do
  local hi = FULL
  while hi - STEP >= LOWEST - 0.001 do
    BANDS[#BANDS + 1] = { lo = hi - STEP, hi = hi, start = hi - STEP / 2 }
    hi = hi - STEP
  end
end
ns.BANDS = BANDS

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

-- the share of health at which a unit has `seconds` left, when it has been losing health
-- evenly for T seconds since it was at `start`: the same rule the seconds themselves follow
local function ShareAt(seconds, T, start) return seconds * start / (seconds + T) end

-- yes below the share, no above it (yesBelow) or the other way round
local function Band(curve, share, yesBelow)
  curve:ClearPoints()
  curve:AddPoint(0, yesBelow and ON or OFF)
  curve:AddPoint(math.min(share, 1), yesBelow and OFF or ON)
end

local function Percent(unit, curve) return pcall(UnitHealthPercent, unit, false, curve) end

-- the game's yes / no as the opacity of a frame or text; false when that did not work
local function Opacity(region, unit, curve)
  local ok, colour = Percent(unit, curve)
  if not ok or type(colour) ~= "table" then return false end
  local okA, _, _, _, a = pcall(colour.GetRGBA, colour)
  return okA and (pcall(region.SetAlpha, region, a)) or false
end

------------------------------------------------------------------------
-- tracks: one unit followed through a fight
------------------------------------------------------------------------
-- A track counts the hits on its unit and holds one frame per band. The game sets the opacity
-- of these frames once, at the first hit: visible for the band the unit was in, invisible for
-- the others. Whatever is shown for the unit sits inside them.
local root            -- parent of all tracks' frames; it carries the size
local targetSlots = {} -- tracks of "target": several, so a target met again keeps its count
local focusTrack
local bossTracks = {}  -- "boss1" ...: followed while an encounter runs, whoever is the target
local cur             -- the track of the current target among targetSlots, or nil
local inCombat = false

local function NewTrack(unit)
  local t = { unit = unit, gates = {}, hits = 0, used = 0, maxHits = 0, asked = 0, failed = 0 }
  for k = 1, #BANDS do
    local g = CreateFrame("Frame", nil, root)
    g:SetAlpha(0)
    t.gates[k] = g
  end
  return t
end

local function Clear(t)
  t.guid, t.hit, t.lastHit, t.hits = nil, nil, nil, 0
  for _, g in ipairs(t.gates) do g:SetAlpha(0) end
end

local function Hit(t)
  if not t then return end
  local now = GetTime()
  t.hits = t.hits + 1
  if t.hits > t.maxHits then t.maxHits = t.hits end
  t.lastHit = now
  if not t.hit then
    t.hit = now
    -- the game marks, once, the band this unit is in now; all other bands stay invisible
    for k, g in ipairs(t.gates) do
      if not Opacity(g, t.unit, bandCurves[k]) then
        for _, x in ipairs(t.gates) do x:SetAlpha(0) end
        t.failed = t.failed + 1
        break
      end
    end
  end
end

local function Hostile(unit)
  return Bool(UnitExists, unit) == true and Bool(UnitCanAttack, "player", unit) == true
    and Bool(UnitIsDeadOrGhost, unit) == false
end

local STRONG = { elite = true, rareelite = true, rare = true, worldboss = true }
local function Wanted(unit, cfg)
  if not cfg.elite then return true end
  if STRONG[Plain(UnitClassification, unit) or ""] then return true end
  return Plain(UnitLevel, unit) == -1
end

local function Ready(t, cfg)
  if not t or not t.hit or t.hits < MIN_HITS then return false end
  if GetTime() - t.hit < MIN_TIME then return false end
  if Bool(UnitExists, t.unit) ~= true or Bool(UnitIsDeadOrGhost, t.unit) ~= false then return false end
  return Wanted(t.unit, cfg)
end

-- the target's own track: found again by its id where the game tells units apart
local useCount = 0
local function TargetChanged()
  cur = nil
  if not Hostile("target") then return end
  local guid = Plain(UnitGUID, "target")
  if type(guid) ~= "string" then guid = nil end
  local best
  for _, t in ipairs(targetSlots) do
    if guid and t.guid == guid then cur = t break end
    if not best or t.used < best.used then best = t end
  end
  if not cur then
    Clear(best)
    best.guid = guid
    cur = best
  end
  useCount = useCount + 1
  cur.used = useCount
end

local function FocusChanged()
  Clear(focusTrack)
end

local function ForgetAll()
  for _, t in ipairs(targetSlots) do Clear(t) t.used = 0 end
  for _, t in ipairs(bossTracks) do Clear(t) end
  Clear(focusTrack)
  useCount = 0
  cur = nil
end

-- is `a` the same unit as `b`? true / false, or nil when the game does not say
local same = { yes = 0, no = 0, unknown = 0 } -- counted for /lbf check
local function Same(a, b)
  if Bool(UnitExists, b) ~= true then return false end
  local r = Bool(UnitIsUnit, a, b)
  if r == true then same.yes = same.yes + 1 elseif r == false then same.no = same.no + 1
  else same.unknown = same.unknown + 1 end
  return r
end

-- the track a frame shows: a boss of the encounter is followed from its first hit, the focus
-- for as long as it is the focus, any other target since it became the target
local function TrackFor(unit)
  for _, t in ipairs(bossTracks) do
    if t.hit and Same(unit, t.unit) == true then return t end
  end
  if unit == "focus" then return focusTrack end
  if db.focus and focusTrack.hit and Same("target", "focus") == true then return focusTrack end
  return cur
end

------------------------------------------------------------------------
-- views: the frames on screen (target, focus)
------------------------------------------------------------------------
local views = {}
local lockBtn, setBtn

-- text with letters ("s", "с", "초"): only the game's own font objects keep every alphabet
local function BigFont(fs)
  for _, name in ipairs({ "GameFontNormalHugeOutline", "GameFontNormalLargeOutline",
                          "GameFontHighlightOutline", "GameFontHighlightLarge" }) do
    if _G[name] then fs:SetFontObject(name) return end
  end
end

-- the settings a frame goes by: the focus frame has its own or follows the target's
local function Cfg(v)
  if v.unit == "focus" and not db.focusSame then return db.f end
  return db
end
ns.Cfg = Cfg

local function Place(v)
  local hud = v.hud
  local scale = Cfg(v).scale
  hud:SetScale(scale)
  hud:ClearAllPoints()
  local p = db[v.pointKey]
  if p then
    -- the point is kept in screen units, so a new size leaves the frame where it is
    hud:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1] / scale, p[2] / scale)
  else
    hud:SetPoint("CENTER", UIParent, "CENTER", 0, v.defaultY / scale)
  end
end

-- tipTitle and tipText are functions: the texts follow a change of language
local function HudButton(parent, text, tipTitle, tipText)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(80, 20)
  Skin.RedButton(b)
  b:SetNormalFontObject("GameFontNormalSmall")
  b:SetHighlightFontObject("GameFontHighlightSmall")
  b:SetText(text)
  local fs = b:GetFontString()
  if fs and fs.GetStringWidth then b:SetWidth(math.max(80, math.ceil(fs:GetStringWidth() or 0) + 20)) end
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tipTitle(), 1, 1, 1)
    GameTooltip:AddLine(tipText(), 0.82, 0.82, 0.82, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  function b:SetLabel(t)
    self:SetText(t)
    local f = self:GetFontString()
    if f and f.GetStringWidth then self:SetWidth(math.max(80, math.ceil(f:GetStringWidth() or 0) + 20)) end
  end
  return b
end

local function HideCells(v)
  for _, c in ipairs(v.cells) do c.frame:Hide() end
end

-- puts the view's seconds inside the frames of a track (or nowhere)
local function Attach(v, track)
  if v.track == track then return end
  v.track = track
  if track then
    for k, c in ipairs(v.cells) do
      c.frame:SetParent(track.gates[k])
      c.frame:ClearAllPoints()
      c.frame:SetAllPoints(v.hud)
    end
  end
  HideCells(v)
end

local function BuildView(unit, pointKey, defaultY, label)
  local v = { unit = unit, pointKey = pointKey, defaultY = defaultY, cells = {} }
  local hud = CreateFrame("Frame", nil, UIParent)
  v.hud = hud
  hud:SetSize(150, 32)
  hud:SetMovable(true)
  hud:SetClampedToScreen(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    if x and y then
      local scale = Cfg(v).scale
      db[pointKey] = { x * scale, y * scale }
      Place(v)
    end
  end)
  -- while unlocked: a dark plate in the addon's colour with a sample
  v.plate = CreateFrame("Frame", nil, hud)
  v.plate:SetAllPoints()
  local bg = v.plate:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(Skin.BG[1], Skin.BG[2], Skin.BG[3], 0.85)
  Skin.Edge(v.plate, Skin.ACCENT, 0.9)
  -- the words and buttons around the unlocked frame keep their size whatever the frame's size:
  -- at 50 % they were too small to read or click
  v.chrome = CreateFrame("Frame", nil, UIParent)
  v.chrome:SetAllPoints(hud)
  v.drag = v.chrome:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  v.drag:SetPoint("BOTTOM", hud, "TOP", 0, 4)
  v.drag:SetText(label)
  v.sample = v.plate:CreateFontString(nil, "OVERLAY")
  BigFont(v.sample)
  v.sampleIcon = v.plate:CreateTexture(nil, "ARTWORK")
  v.sampleIcon:SetSize(26, 26)
  v.sampleIcon:SetPoint("LEFT", hud, "LEFT", 3, 0)
  v.sampleIcon:SetTexture(Skin.LOGO)
  -- the seconds of each band; the opacity of a cell follows "Show from", set anew by the
  -- game on every update
  for k = 1, #BANDS do
    local c = {}
    c.frame = CreateFrame("Frame", nil, root)
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
    if unit ~= "target" then
      -- a small word over the seconds tells the second frame from the first
      c.tag = c.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      c.tag:SetPoint("BOTTOM", hud, "TOP", 0, 1)
      c.tag:SetText(label)
    end
    c.frame:Hide()
    v.cells[k] = c
  end
  views[#views + 1] = v
  return v
end

local function Enabled(v) return v.unit == "target" or db.focus end

function ns.Apply()
  local unlocked = not db.locked
  for _, v in ipairs(views) do
    local cfg = Cfg(v)
    local point, x = "CENTER", 0
    if cfg.icon then point, x = "LEFT", 34 end -- with the icon the seconds stand right of it
    Place(v)
    local on = Enabled(v)
    v.hud:SetShown(on)
    v.hud:EnableMouse(unlocked and on)
    v.plate:SetShown(unlocked and on)
    v.chrome:SetShown(unlocked and on)
    v.sampleIcon:SetShown(cfg.icon)
    v.sample:ClearAllPoints()
    v.sample:SetPoint(point, v.hud, point, x, 0)
    v.sample:SetText(string.format(L.fmtSec, 12))
    for _, c in ipairs(v.cells) do
      -- the seconds sit inside a track's frames, not inside the frame on screen: they get
      -- the frame's size themselves
      c.frame:SetScale(cfg.scale)
      c.frame:ClearAllPoints()
      c.frame:SetAllPoints(v.hud)
      c.icon:SetShown(cfg.icon)
      c.textN:ClearAllPoints()
      c.textN:SetPoint(point, v.hud, point, x, 0)
      c.textU:ClearAllPoints()
      c.textU:SetAllPoints(c.textN)
    end
    if not on or unlocked then HideCells(v) end
  end
  lockBtn:SetShown(unlocked)
  setBtn:SetShown(unlocked)
end

function ns.SetLocked(locked, quiet)
  db.locked = locked and true or false
  ns.Apply()
  if not quiet then Print("%s", db.locked and L.msgLocked or L.msgUnlocked) end
  if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.ResetPosition()
  db.point, db.focusPoint = nil, nil
  ns.Apply()
  Print("%s", L.msgReset)
end

-- the texts on screen after a change of language
function ns.OnLanguageChanged()
  for _, v in ipairs(views) do
    v.drag:SetText(v.unit == "target" and L.hudDrag or L.hudFocus)
    for _, c in ipairs(v.cells) do
      if c.tag then c.tag:SetText(L.hudFocus) end
      -- the seconds are written anew on the next update, in the new language
    end
  end
  lockBtn:SetLabel(L.optLock)
  setBtn:SetLabel(L.hudSettings)
  ns.Apply()
end

local function BuildAll()
  root = CreateFrame("Frame", nil, UIParent)
  root:SetSize(1, 1)
  root:SetPoint("CENTER")
  for i = 1, SLOTS do targetSlots[i] = NewTrack("target") end
  focusTrack = NewTrack("focus")
  for i = 1, BOSSES do bossTracks[i] = NewTrack("boss" .. i) end
  local main = BuildView("target", "point", 140, L.hudDrag)
  BuildView("focus", "focusPoint", 100, L.hudFocus)
  lockBtn = HudButton(main.chrome, L.optLock, function() return L.optLock end, function() return L.tipHudLock end)
  lockBtn:SetPoint("TOPRIGHT", main.hud, "BOTTOM", -2, -5)
  lockBtn:SetScript("OnClick", function() ns.SetLocked(true) end)
  setBtn = HudButton(main.chrome, L.hudSettings, function() return L.hudSettings end, function() return L.tipHudSettings end)
  setBtn:SetPoint("TOPLEFT", main.hud, "BOTTOM", 2, -5)
  setBtn:SetScript("OnClick", function() if ns.ToggleOptions then ns.ToggleOptions(true) end end)
  ns.views, ns.hud, ns.cells = views, main.hud, main.cells
  ns.targetSlots, ns.focusTrack, ns.bossTracks = targetSlots, focusTrack, bossTracks
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
-- the seconds of one band of a view: text, "Show from", red or white
local function ShowBand(v, t, k, T, cfg)
  local b, c, unit = BANDS[k], v.cells[k], t.unit
  ttdCurve:ClearPoints()
  ttdCurve:AddPoint(0, 0)
  for i = 1, #SECONDS do
    local s = SECONDS[i]
    ttdCurve:AddPoint(ShareAt(s, T, b.start), s)
  end
  ttdCurve:AddPoint(1, CAP)
  local ok, seconds = Percent(unit, ttdCurve)
  if not ok then return false end
  local okT, text = pcall(string.format, L.fmtSec, seconds)
  if not okT then return false end
  c.textN:SetText(text)
  c.textU:SetText(text)
  -- "Show from": hidden while more than the limit is left, and until the unit has lost
  -- enough for an estimate (LOST below full, or below the band it was in at its first hit)
  local limit = cfg.limit > 0 and cfg.limit or CAP
  local top = (k == 1 and 1 or b.lo) - LOST
  Band(limitCurve, math.min(ShareAt(limit, T, b.start), top), true)
  if not Opacity(c.frame, unit, limitCurve) then return false end
  -- "Last seconds in red": the red text below the mark, the white one above it
  if cfg.urgent > 0 then
    local share = ShareAt(cfg.urgent, T, b.start)
    Band(urgentCurve, share, true)
    Band(normalCurve, share, false)
    if not (Opacity(c.textU, unit, urgentCurve) and Opacity(c.textN, unit, normalCurve)) then return false end
  else
    c.textU:SetAlpha(0)
    c.textN:SetAlpha(1)
  end
  return true
end

local function ShowView(v, t, cfg)
  -- the first hit already took its share of health but no time: count one average gap
  -- between hits before it
  local start = t.hit - (t.lastHit - t.hit) / (t.hits - 1)
  local T = GetTime() - start
  t.asked = t.asked + 1
  for k = 1, #BANDS do
    if not ShowBand(v, t, k, T, cfg) then
      t.failed = t.failed + 1
      return false
    end
  end
  return true
end

-- test builds: in a boss fight a screenshot every SHOT_EVERY seconds while the target's
-- seconds are worked out, for checking them against the fight afterwards (and for pictures); /lbf shots
local encounter -- the id of the running encounter, or nil
local SHOT_EVERY, SHOT_MAX = 10, 80
local lastShot, shotCount = 0, 0
local function MaybeShot()
  if not db.shots or not encounter or shotCount >= SHOT_MAX or type(Screenshot) ~= "function" then return end
  local now = GetTime()
  if now - lastShot < SHOT_EVERY then return end
  lastShot = now
  if pcall(Screenshot) then shotCount = shotCount + 1 end
end

local function Update()
  for _, v in ipairs(views) do
    local t = nil
    if db.locked and Enabled(v) and Hostile(v.unit) then t = TrackFor(v.unit) end
    Attach(v, t)
    local cfg = Cfg(v)
    if Ready(t, cfg) and ShowView(v, t, cfg) then
      for _, c in ipairs(v.cells) do c.frame:Show() end
      if v.unit == "target" then MaybeShot() end
    else
      HideCells(v)
      if t and t.failed > 0 then Broken() end
    end
  end
end
ns.Update = Update

------------------------------------------------------------------------
-- what the game answered (for bug reports): /lbf check
------------------------------------------------------------------------
local function Yn(v) if v == true then return "y" elseif v == false then return "n" end return "?" end

local function CheckLine(why)
  local parts = { date("%H:%M:%S"), why, "enc=" .. tostring(encounter or "-") }
  local function add(name, t)
    parts[#parts + 1] = string.format("%s[hits=%d asked=%d failed=%d]", name, t.maxHits, t.asked, t.failed)
    t.maxHits, t.asked, t.failed = 0, 0, 0
  end
  local best = targetSlots[1]
  for _, t in ipairs(targetSlots) do if t.maxHits > best.maxHits then best = t end end
  add("target", best)
  for _, t in ipairs(targetSlots) do t.maxHits, t.asked, t.failed = 0, 0, 0 end
  add("focus", focusTrack)
  for i, t in ipairs(bossTracks) do
    if i == 1 or t.maxHits > 0 then add(t.unit, t) end
  end
  parts[#parts + 1] = string.format("same[y=%d n=%d ?=%d]", same.yes, same.no, same.unknown)
  same.yes, same.no, same.unknown = 0, 0, 0
  parts[#parts + 1] = string.format("now[boss1=%s focus=%s guid=%s]", Yn(Bool(UnitExists, "boss1")),
    Yn(Bool(UnitExists, "focus")), type(Plain(UnitGUID, "target")) == "string" and "plain" or "hidden")
  local list = db.checks
  list[#list + 1] = table.concat(parts, " ")
  while #list > 30 do table.remove(list, 1) end
end
ns.CheckLine = CheckLine

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
    for _, v in ipairs(views) do HideCells(v) end
    Broken()
  end
end)

-- hits: one listener per followed unit, so each track counts the hits on its own unit
local function Listen(unit, onHit)
  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", function(_, _, u, action)
    if ready and u == unit and not IsSecret(action) and action == "WOUND" then onHit() end
  end)
  if not pcall(f.RegisterUnitEvent, f, "UNIT_COMBAT", unit) then pcall(f.RegisterEvent, f, "UNIT_COMBAT") end
end

local function OnEvent(_, event, a1)
  if event == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    InitDB()
    BuildAll()
    ready = InitCurves()
    if not ready then Broken() end
    ns.Apply()
    Listen("target", function() Hit(cur) end)
    Listen("focus", function() Hit(focusTrack) end)
    for _, t in ipairs(bossTracks) do Listen(t.unit, function() Hit(t) end) end
    if ns.InitOptions then ns.InitOptions() end
  elseif not ready then
    return
  elseif event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    -- a fight never starts with the frames unlocked under the cursor
    if not db.locked then ns.SetLocked(true, true) end
    if not cur then TargetChanged() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    CheckLine("fight")
    ForgetAll()
    TargetChanged()
  elseif event == "PLAYER_TARGET_CHANGED" then
    TargetChanged()
  elseif event == "PLAYER_FOCUS_CHANGED" then
    FocusChanged()
  elseif event == "ENCOUNTER_START" then
    encounter = Plain(function() return a1 end) or 0
    for _, t in ipairs(bossTracks) do Clear(t) end
  elseif event == "ENCOUNTER_END" then
    CheckLine("boss")
    encounter = nil
    for _, t in ipairs(bossTracks) do Clear(t) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    inCombat = Bool(InCombatLockdown) == true
    if inCombat and not db.locked then ns.SetLocked(true, true) end
    ForgetAll()
    TargetChanged()
  end
end
ev:SetScript("OnEvent", OnEvent)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
                     "PLAYER_FOCUS_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_ENTERING_WORLD" }) do
  pcall(ev.RegisterEvent, ev, e)
end

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
  elseif msg == "shots" then
    db.shots = not db.shots
    Print("screenshots %s (boss fights only, every %d s, at most %d)", db.shots and "ON" or "off", SHOT_EVERY, SHOT_MAX)
  elseif msg == "check" then
    Print("v%s, %d lines:", ns.VERSION, #db.checks)
    for i = math.max(1, #db.checks - 7), #db.checks do DEFAULT_CHAT_FRAME:AddMessage(db.checks[i]) end
  elseif msg == "help" or msg == "?" then
    for _, k in ipairs({ "help1", "help2", "help3", "help4", "help5" }) do Print("%s", L[k]) end
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
