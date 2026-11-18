-- Last Breath Forever - about how many seconds the current target has left.
-- The target's health is secret for addons: nothing here compares it or calculates with it.
-- The game works the seconds out itself and hands back a value that can only be shown.

local ADDON, ns = ...
ns.VERSION = "0.2.0"
local L = ns.L
local Skin = ns.Skin

local TICK = 0.2
local MIN_HITS = 3         -- hits on the target before an estimate shows
local MIN_TIME = 2         -- seconds since the first hit before an estimate shows
local FULL = 0.90          -- a target taken out of combat counts as full from here up
local STEP = 0.025         -- other targets: bands of this width, each with its own estimate
local LOWEST = 0.20        -- a target first hit below this share gets no estimate
-- how much must be lost since the start before a number shows. Solo: 5 % (a target that
-- was already hurt: 7.5 % below its band's middle). In a group or on a boss the damage
-- needs time to build up: after 10 s and 3 % (hurt: 7.5 %), or earlier once 20 % is lost
local LOST_SOLO, LOST_HURT = 0.05, 0.075
local GROUP_TIME, LOST_GROUP, LOST_EARLY = 10, 0.03, 0.20
local CAP = 3600           -- the longest estimate (seconds)
local SLOTS = 8            -- targets remembered during one fight
local PLATES = 20          -- enemies followed by their nameplates at once
ns.LIMITS = { 0, 30, 60, 120, 300, 600 } -- "Show from": 0 = always
ns.URGENTS = { 0, 5, 10, 15, 20, 30, 45, 60 } -- "Last seconds in red": 0 = off
-- longer times read as minutes: "~2:30" (to 10 s) from LONG s up, "~12 min" from MINUTES s up
local LONG, MINUTES = 90, 600
local SECONDS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 25, 30, 35, 40, 50, 60,
  75, 90, 120, 150, 180, 240, 300, 450, 600, 900, 1200, 1800, 2700, 3600 }

local DEFAULTS = {
  locked = true,
  scale = 1,       -- size of the seconds and the icon
  icon = true,
  limit = 300,     -- seconds: show from here down (0 = always)
  urgent = 10,     -- seconds: red from here down (0 = off)
  elite = false,   -- only elite, rare and boss targets
  focus = false,   -- a second frame for the focus
  focusSame = true, -- the focus frame uses the target frame's settings
  plates = true,   -- follow enemies by their nameplates, also while they are not the target
  onPlate = false, -- the target frame above the target's nameplate
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

-- where bugs go: named after help, after /lbf check and with the warning
local BUG_URL = "https://github.com/KesaObscura/LastBreathForever/issues"
ns.BUG_URL = BUG_URL
local function BugLink() Print(L.bugReport, BUG_URL) end

local warned
local function Broken()
  if not warned then
    warned = true
    Print("%s", L.warnBroken)
    BugLink()
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
  db.shots = nil -- a switch of the test builds
  ns.db = db
end

------------------------------------------------------------------------
-- bands
------------------------------------------------------------------------
-- The addon cannot read how much health a unit had when it was first hit, so the health scale
-- is cut into bands: BANDS[k] = { lo, hi, start } (start = the share the estimate of that band
-- counts from). The game marks, once, the band the unit is in at its first hit; every band
-- has its own seconds on screen, and only the marked band's are seen.
-- Band 1 is "full" (90-100 %, counted from 100 %): only for a unit taken out of combat, whose
-- first hit may already take a big bite. A unit already fighting uses 2.5 % bands from 100 %
-- down (a mob at 91 % after an AoE is not taken for full).
local BANDS = { { lo = FULL, hi = 1.01, start = 1, full = true } }
do
  local hi = 1
  while hi - STEP >= LOWEST - 0.001 do
    BANDS[#BANDS + 1] = { lo = hi - STEP, hi = hi >= 1 and 1.01 or hi, start = hi - STEP / 2 }
    hi = hi - STEP
  end
end
-- the bands a unit can be in: taken out of combat, or already fighting
local FRESH, FIGHTING = { 1 }, {}
for k = 2, #BANDS do
  FIGHTING[#FIGHTING + 1] = k
  if BANDS[k].hi <= FULL + 0.001 then FRESH[#FRESH + 1] = k end
end
ns.BANDS = BANDS

------------------------------------------------------------------------
-- what the game is asked
------------------------------------------------------------------------
local ttdCurve, limitCurve, urgentCurve, normalCurve, waitCurve
local formCurve, minCurve, tenCurve -- which of the three texts, and the minutes and tens of "~2:30"
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
  limitCurve, urgentCurve, normalCurve, waitCurve = NewCurve(true), NewCurve(true), NewCurve(true), NewCurve(true)
  formCurve = NewCurve(true)
  minCurve, tenCurve = NewCurve(false), NewCurve(false)
  if minCurve then pcall(minCurve.SetType, minCurve, Enum.LuaCurveType.Step) end
  if tenCurve then pcall(tenCurve.SetType, tenCurve, Enum.LuaCurveType.Step) end
  if not (ttdCurve and limitCurve and urgentCurve and normalCurve and waitCurve and formCurve
      and minCurve and tenCurve and CreateColor) then return false end
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
local cur             -- the track of the current target among targetSlots, or nil
-- enemies with a nameplate: counted from their first hit while they are not the target, so
-- their seconds are there the moment they become it (also in dungeons, where a target met
-- again cannot be told apart otherwise)
local plateTracks = {} -- [nameplate token] = track
local platePool = {}   -- free tracks
local platesOf = {}    -- ["target"] / ["focus"] = the track of that unit's nameplate, or nil
local plateStat = { seen = 0, hits = 0, yes = 0, no = 0, unknown = 0 } -- for /lbf check
local inCombat = false
local encounter       -- the id of the running boss encounter, or nil

local function NewTrack(unit)
  local t = { unit = unit, gates = {}, hits = 0, used = 0, maxHits = 0, asked = 0, failed = 0, bands = FIGHTING }
  for k = 1, #BANDS do
    local g = CreateFrame("Frame", nil, root)
    g:SetAlpha(0)
    t.gates[k] = g
  end
  return t
end

-- was the unit out of combat when its count began? yes / no / nil (the game did not say)
local fights = { yes = 0, no = 0, unknown = 0 } -- counted for /lbf check
local function Fighting(unit)
  local r = Bool(UnitAffectingCombat, unit)
  if r == true then fights.yes = fights.yes + 1 elseif r == false then fights.no = fights.no + 1
  else fights.unknown = fights.unknown + 1 end
  return r
end

-- a new count for the unit now in this track
local function Clear(t)
  t.guid, t.hit, t.lastHit, t.hits = nil, nil, nil, 0
  for _, g in ipairs(t.gates) do g:SetAlpha(0) end
  -- only a unit known to be out of combat may count as full (when the game does not say:
  -- the narrow bands, which cost at most 1.25 % on a full one)
  t.bands = (Bool(UnitExists, t.unit) == true and Fighting(t.unit) == false) and FRESH or FIGHTING
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
    for _, k in ipairs(t.bands) do
      if not Opacity(t.gates[k], t.unit, bandCurves[k]) then
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

-- counting: the unit has been hit and is alive and wanted. Ready: enough hits and time
local function Counting(t, cfg)
  if not t or not t.hit then return false end
  if Bool(UnitExists, t.unit) ~= true or Bool(UnitIsDeadOrGhost, t.unit) ~= false then return false end
  return Wanted(t.unit, cfg)
end
local function Ready(t)
  return t.hits >= MIN_HITS and GetTime() - t.hit >= MIN_TIME
end

-- a group or a boss: damage builds up over the first seconds (the tank alone, then everyone)
local function Grouped(unit)
  if encounter then return true end
  local n = Plain(GetNumGroupMembers)
  if type(n) == "number" and n > 0 then return true end
  return Plain(UnitLevel, unit) == -1 or Plain(UnitClassification, unit) == "worldboss"
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
    best.unit = "target"
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

-- which nameplate is the target and which the focus (nil: none, or the game does not say)
local function FindPlates()
  for _, unit in ipairs({ "target", "focus" }) do
    platesOf[unit] = nil
    if db.plates and Bool(UnitExists, unit) == true then
      for token, t in pairs(plateTracks) do
        local r = Bool(UnitIsUnit, unit, token)
        if r == true then plateStat.yes = plateStat.yes + 1 platesOf[unit] = t break
        elseif r == false then plateStat.no = plateStat.no + 1
        else plateStat.unknown = plateStat.unknown + 1 end
      end
    end
  end
end

local function PlateAdded(token)
  if not db.plates or type(token) ~= "string" or plateTracks[token] then return end
  if not Hostile(token) then return end
  local t = table.remove(platePool)
  if not t then
    local n = 0
    for _ in pairs(plateTracks) do n = n + 1 end
    if n >= PLATES then return end
    t = NewTrack(token)
  end
  t.unit = token
  Clear(t)
  plateTracks[token] = t
  plateStat.seen = plateStat.seen + 1
end

local function PlateRemoved(token)
  local t = plateTracks[token]
  if not t then return end
  plateTracks[token] = nil
  Clear(t)
  platePool[#platePool + 1] = t
  for unit, x in pairs(platesOf) do if x == t then platesOf[unit] = nil end end
end

local function PlateHit(token)
  local t = plateTracks[token]
  if not t then return end
  plateStat.hits = plateStat.hits + 1
  Hit(t)
end

local function ForgetAll()
  for _, t in ipairs(targetSlots) do Clear(t) t.used = 0 end
  for _, t in pairs(plateTracks) do Clear(t) end
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

-- the track a frame shows. Target, focus and a nameplate can all be the same enemy: then the
-- count that began first (the longest) is used, in both frames alike, never two counts mixed
local function TrackFor(unit)
  local best = unit == "focus" and focusTrack or cur
  local function take(t)
    if t and t.hit and not (best and best.hit and best.hit <= t.hit) then best = t end
  end
  take(platesOf[unit])
  if unit == "target" and db.focus and focusTrack.hit and Same("target", "focus") == true then
    take(focusTrack)
    take(platesOf.focus)
  elseif unit == "focus" and cur and cur.hit and Same("focus", "target") == true then
    take(cur)
    take(platesOf.target)
  end
  return best
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

-- the target's nameplate frame, when the game shows one
local function TargetPlateFrame()
  local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
  if type(get) ~= "function" then return nil end
  local ok, f = pcall(get, "target")
  if not ok or IsSecret(f) or type(f) ~= "table" then return nil end
  return f
end

local function Place(v)
  local hud = v.hud
  local scale = Cfg(v).scale
  hud:SetScale(scale)
  hud:ClearAllPoints()
  local p = db[v.pointKey]
  -- above the target's nameplate while locked; its own place while unlocked or without one
  local plate = v.unit == "target" and db.onPlate and db.locked and TargetPlateFrame()
  v.onPlate = plate and true or false
  if plate and pcall(hud.SetPoint, hud, "BOTTOM", plate, "TOP", 0, 2) then
    return
  end
  v.onPlate = false
  hud:ClearAllPoints()
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
  v.longAt = nil -- the minutes texts of the new unit are written at once
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
  -- the words and buttons around the unlocked frame keep their size whatever the frame's size:
  -- at 50 % they were too small to read or click
  v.chrome = CreateFrame("Frame", nil, UIParent)
  v.chrome:SetAllPoints(hud)
  -- the outline too: a 1 px line inside a frame at 50-90 % got thinner than a pixel and was
  -- drawn uneven or not at all
  for _, t in ipairs(Skin.Edge(v.chrome, Skin.ACCENT, 0.9)) do
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, true) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
  end
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
    -- the number (its opacity: "Show from" and enough lost) and, while it waits, a dim icon
    -- (or a dim "...") that says "counting"
    c.num = CreateFrame("Frame", nil, c.frame)
    c.num:SetAllPoints(hud)
    c.wait = CreateFrame("Frame", nil, c.frame)
    c.wait:SetAllPoints(hud)
    c.waitIcon = c.wait:CreateTexture(nil, "ARTWORK")
    c.waitIcon:SetSize(26, 26)
    c.waitIcon:SetPoint("LEFT", hud, "LEFT", 3, 0)
    c.waitIcon:SetTexture(Skin.LOGO)
    c.waitIcon:SetAlpha(0.55)
    c.waitText = c.wait:CreateFontString(nil, "OVERLAY")
    BigFont(c.waitText)
    c.waitText:SetText("...")
    c.waitText:SetAlpha(0.55)
    c.icon = c.num:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(26, 26)
    c.icon:SetPoint("LEFT", hud, "LEFT", 3, 0)
    c.icon:SetTexture(Skin.LOGO)
    -- three ways to write the time, each in its own frame that the game shows or hides:
    -- seconds (white, or red at the end), "~2:30", "~12 min"
    c.sec = CreateFrame("Frame", nil, c.num)
    c.sec:SetAllPoints(hud)
    c.mss = CreateFrame("Frame", nil, c.num)
    c.mss:SetAllPoints(hud)
    c.mins = CreateFrame("Frame", nil, c.num)
    c.mins:SetAllPoints(hud)
    c.textL = c.mss:CreateFontString(nil, "OVERLAY")
    BigFont(c.textL)
    c.textL:SetTextColor(1, 1, 1)
    c.textM = c.mins:CreateFontString(nil, "OVERLAY")
    BigFont(c.textM)
    c.textM:SetTextColor(1, 1, 1)
    c.textN = c.sec:CreateFontString(nil, "OVERLAY")
    BigFont(c.textN)
    c.textN:SetTextColor(1, 1, 1)
    c.textU = c.sec:CreateFontString(nil, "OVERLAY")
    BigFont(c.textU)
    c.textU:SetTextColor(1, 0.25, 0.30)
    c.textU:SetAlpha(0)
    if unit ~= "target" then
      -- a small word over the seconds tells the second frame from the first
      c.tag = c.num:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
  if not db.plates then
    for token in pairs(plateTracks) do PlateRemoved(token) end
  end
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
      c.waitIcon:SetShown(cfg.icon)
      c.waitText:SetShown(not cfg.icon)
      c.waitText:ClearAllPoints()
      c.waitText:SetPoint("CENTER", v.hud, "CENTER", 0, 0)
      c.textN:ClearAllPoints()
      c.textN:SetPoint(point, v.hud, point, x, 0)
      c.textU:ClearAllPoints()
      c.textU:SetAllPoints(c.textN)
      for _, fs in ipairs({ c.textL, c.textM }) do
        fs:ClearAllPoints()
        fs:SetPoint(point, v.hud, point, x, 0)
      end
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
  local main = BuildView("target", "point", 140, L.hudDrag)
  BuildView("focus", "focusPoint", 100, L.hudFocus)
  lockBtn = HudButton(main.chrome, L.optLock, function() return L.optLock end, function() return L.tipHudLock end)
  lockBtn:SetPoint("TOPRIGHT", main.hud, "BOTTOM", -2, -5)
  lockBtn:SetScript("OnClick", function() ns.SetLocked(true) end)
  setBtn = HudButton(main.chrome, L.hudSettings, function() return L.hudSettings end, function() return L.tipHudSettings end)
  setBtn:SetPoint("TOPLEFT", main.hud, "BOTTOM", 2, -5)
  setBtn:SetScript("OnClick", function() if ns.ToggleOptions then ns.ToggleOptions(true) end end)
  ns.views, ns.hud, ns.cells = views, main.hud, main.cells
  ns.targetSlots, ns.focusTrack, ns.plateTracks = targetSlots, focusTrack, plateTracks
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
-- the seconds of one band of a view: text, "Show from", red or white
local function ShowBand(v, t, k, T, cfg, long)
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
  -- enough for an estimate; while it waits for that, the dim "counting" sign
  local lost
  if Grouped(unit) then
    lost = T >= GROUP_TIME and (b.full and LOST_GROUP or LOST_HURT) or LOST_EARLY
  else
    lost = b.full and LOST_SOLO or LOST_HURT
  end
  local top = b.start - lost
  local limit = cfg.limit > 0 and cfg.limit or CAP
  Band(limitCurve, math.min(ShareAt(limit, T, b.start), top), true)
  if not Opacity(c.num, unit, limitCurve) then return false end
  Band(waitCurve, top, false)
  if not Opacity(c.wait, unit, waitCurve) then return false end
  -- which text: seconds below LONG, "~2:30" up to MINUTES, "~12 min" above
  if limit > LONG then
    local hLong, hMin = ShareAt(LONG, T, b.start), ShareAt(MINUTES, T, b.start)
    Band(formCurve, hLong, true)
    if not Opacity(c.sec, unit, formCurve) then return false end
    formCurve:ClearPoints()
    formCurve:AddPoint(0, OFF)
    formCurve:AddPoint(hLong, ON)
    formCurve:AddPoint(math.min(hMin, 1), OFF)
    if not Opacity(c.mss, unit, formCurve) then return false end
    if limit > MINUTES then
      Band(formCurve, hMin, false)
      if not Opacity(c.mins, unit, formCurve) then return false end
    else
      c.mins:SetAlpha(0)
    end
    -- the minutes texts change at most every 10 s: written once a second
    if long then
      -- "~2:30": rounded to 10 s. D = 100, 110, ... starts at D - 5 s
      minCurve:ClearPoints()
      tenCurve:ClearPoints()
      minCurve:AddPoint(0, 1)
      tenCurve:AddPoint(0, 3)
      for D = 100, MINUTES - 10, 10 do
        local h = ShareAt(D - 5, T, b.start)
        minCurve:AddPoint(h, math.floor(D / 60))
        tenCurve:AddPoint(h, (D % 60) / 10)
      end
      local okM, m = Percent(unit, minCurve)
      local okD, d = Percent(unit, tenCurve)
      if not (okM and okD) then return false end
      local okL, txt = pcall(string.format, L.fmtMss, m, d)
      if not okL then return false end
      c.textL:SetText(txt)
      if limit > MINUTES then
        -- "~12 min": rounded to the minute
        minCurve:ClearPoints()
        minCurve:AddPoint(0, MINUTES / 60)
        for M = MINUTES / 60 + 1, CAP / 60 do
          minCurve:AddPoint(ShareAt(M * 60 - 30, T, b.start), M)
        end
        local okN, n = Percent(unit, minCurve)
        if not okN then return false end
        local okT2, txt2 = pcall(string.format, L.fmtMin, n)
        if not okT2 then return false end
        c.textM:SetText(txt2)
      end
    end
  else
    c.sec:SetAlpha(1)
    c.mss:SetAlpha(0)
    c.mins:SetAlpha(0)
  end
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
  local now = GetTime()
  local long = now - (v.longAt or 0) >= 1
  if long then v.longAt = now end
  for _, k in ipairs(t.bands) do
    if not ShowBand(v, t, k, T, cfg, long) then
      t.failed = t.failed + 1
      return false
    end
  end
  return true
end

local function Update()
  -- the target frame follows the target's nameplate as it comes and goes
  if db.onPlate and db.locked and views[1] then
    local want = TargetPlateFrame() and true or false
    if want ~= views[1].onPlate then Place(views[1]) end
  end
  for _, v in ipairs(views) do
    local t = nil
    if db.locked and Enabled(v) and Hostile(v.unit) then t = TrackFor(v.unit) end
    Attach(v, t)
    local cfg = Cfg(v)
    if Counting(t, cfg) then
      if Ready(t) then
        if not ShowView(v, t, cfg) then
          HideCells(v)
          Broken()
          t = nil
        end
      else
        -- a few hits or seconds still missing: only the "counting" sign
        for _, c in ipairs(v.cells) do c.num:SetAlpha(0) c.wait:SetAlpha(1) end
      end
      if t then for _, c in ipairs(v.cells) do c.frame:Show() end end
    else
      HideCells(v)
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
  -- nameplates: how many enemies were followed, hits on them, did the game say which is the target
  parts[#parts + 1] = string.format("plates[seen=%d hits=%d target y=%d n=%d ?=%d frame=%s]", plateStat.seen,
    plateStat.hits, plateStat.yes, plateStat.no, plateStat.unknown, TargetPlateFrame() and "y" or "n")
  for k in pairs(plateStat) do plateStat[k] = 0 end
  parts[#parts + 1] = string.format("same[y=%d n=%d ?=%d]", same.yes, same.no, same.unknown)
  same.yes, same.no, same.unknown = 0, 0, 0
  -- did the game say whether a unit was already fighting when its count began?
  parts[#parts + 1] = string.format("fighting[y=%d n=%d ?=%d]", fights.yes, fights.no, fights.unknown)
  fights.yes, fights.no, fights.unknown = 0, 0, 0
  local n = Plain(GetNumGroupMembers)
  parts[#parts + 1] = string.format("now[focus=%s guid=%s group=%s]", Yn(Bool(UnitExists, "focus")),
    type(Plain(UnitGUID, "target")) == "string" and "plain" or "hidden", tostring(n or "?"))
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
    -- hits on enemies with a nameplate
    local pf = CreateFrame("Frame")
    pf:SetScript("OnEvent", function(_, _, u, action)
      if ready and db.plates and type(u) == "string" and u:find("^nameplate%d") and not IsSecret(action)
          and action == "WOUND" then PlateHit(u) end
    end)
    pcall(pf.RegisterEvent, pf, "UNIT_COMBAT")
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
    FindPlates()
    if views[1] then Place(views[1]) end
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    PlateAdded(a1)
    FindPlates()
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    PlateRemoved(a1)
  elseif event == "PLAYER_FOCUS_CHANGED" then
    FocusChanged()
    FindPlates()
  elseif event == "ENCOUNTER_START" then
    encounter = Plain(function() return a1 end) or 0
  elseif event == "ENCOUNTER_END" then
    CheckLine("boss")
    encounter = nil
  elseif event == "PLAYER_ENTERING_WORLD" then
    inCombat = Bool(InCombatLockdown) == true
    if inCombat and not db.locked then ns.SetLocked(true, true) end
    ForgetAll()
    TargetChanged()
  end
end
ev:SetScript("OnEvent", OnEvent)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
                     "PLAYER_FOCUS_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_ENTERING_WORLD",
                     "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
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
  elseif msg == "check" then
    Print("v%s, %d lines:", ns.VERSION, #db.checks)
    for i = math.max(1, #db.checks - 7), #db.checks do DEFAULT_CHAT_FRAME:AddMessage(db.checks[i]) end
    BugLink()
  elseif msg == "help" or msg == "?" then
    for _, k in ipairs({ "help1", "help2", "help3", "help4", "help5" }) do Print("%s", L[k]) end
    BugLink()
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
