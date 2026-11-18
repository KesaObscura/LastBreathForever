-- Last Breath Forever - the settings window. Plain frames in the look of the series (Skin.lua).

local _, ns = ...
local L = ns.L
local Skin = ns.Skin
local GOLD, GREY = Skin.GOLD, Skin.GREY

local COL, PAD, ROW = 370, 18, 30   -- three columns: target | focus | nameplates
local W = 3 * COL
local VALUE_X = 214 -- where the values of the steppers start, from the label's left edge
local win
local registry = {} -- everything with a Refresh (made anew with the window)
local openList    -- the open list of a dropdown: one at a time

local function Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

-- tooltip on hover, also on greyed-out controls: it says what the setting does
local function Tip(frame, title, text)
  if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
  frame.tipTitle, frame.tipText = title, text
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(text, 0.82, 0.82, 0.82, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function TipArea(parent, fs, title, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(fs)
  f:EnableMouse(true)
  Tip(f, title, text)
  return f
end

local function FitWidth(b, minW)
  local fs = b:GetFontString()
  if fs and fs.GetStringWidth then b:SetWidth(math.max(minW, math.ceil(fs:GetStringWidth() or 0) + 20)) end
end

local function Button(parent, text, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 22)
  Skin.RedButton(b)
  b:SetNormalFontObject("GameFontNormalSmall")
  b:SetHighlightFontObject("GameFontHighlightSmall")
  b:SetDisabledFontObject("GameFontDisableSmall")
  b:SetText(text)
  FitWidth(b, w)
  return b
end

local function ArrowButton(parent, dir)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  if not Skin.Arrow(b, dir) then
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.15, 0.13, 0.95)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.2)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetText(dir < 0 and "-" or "+")
  end
  return b
end

-- enabledIf(): false greys the control out (it keeps its tooltip)
local function Check(parent, text, tip, get, set, enabledIf)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(24, 24)
  if not Skin.Check(cb) then
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  end
  cb.label = Label(parent, text)
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  -- the label is part of the box: a click on it ticks the box
  cb:SetHitRectInsets(0, -math.ceil((cb.label:GetStringWidth() or 0) + 4), 0, 0)
  Tip(cb, text, tip)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    ns.RefreshOptions()
  end)
  cb.Refresh = function()
    cb:SetChecked(get() and true or false)
    local on = not enabledIf or enabledIf()
    cb:SetEnabled(on)
    cb:SetAlpha(on and 1 or 0.5)
    local c = on and GOLD or GREY
    cb.label:SetTextColor(c[1], c[2], c[3])
  end
  registry[#registry + 1] = cb
  return cb
end

-- "Label:   ◄ [ value ] ►"; o.next(v, dir) gives the next value (the same one at the end)
local function Stepper(parent, text, tip, get, set, o, enabledIf)
  local s = {}
  s.label = Label(parent, text .. ":")
  s.minus = ArrowButton(parent, -1)
  s.minus:SetPoint("LEFT", s.label, "LEFT", VALUE_X, 0)
  s.field = CreateFrame("Frame", nil, parent)
  s.field:SetSize(64, 20)
  s.field:SetPoint("LEFT", s.minus, "RIGHT", 4, 0)
  Skin.Field(s.field)
  s.value = Label(s.field, "", "GameFontHighlight")
  s.value:SetPoint("CENTER")
  s.plus = ArrowButton(parent, 1)
  s.plus:SetPoint("LEFT", s.field, "RIGHT", 4, 0)
  s.tipArea = TipArea(parent, s.label, text, tip)
  Tip(s.minus, text, tip)
  Tip(s.plus, text, tip)
  local function change(dir)
    local v = get()
    local nv = o.next(v, dir)
    if nv ~= v then set(nv) end
    ns.RefreshOptions()
  end
  s.minus:SetScript("OnClick", function() change(-1) end)
  s.plus:SetScript("OnClick", function() change(1) end)
  s.Refresh = function()
    local v = get()
    s.value:SetText(o.fmt(v))
    local live = not enabledIf or enabledIf()
    local c = live and GOLD or GREY
    s.label:SetTextColor(c[1], c[2], c[3])
    s.field:SetAlpha(live and 1 or 0.5)
    -- a button that would change nothing is greyed out
    for _, b in ipairs({ { s.minus, -1 }, { s.plus, 1 } }) do
      local on = live and o.next(v, b[2]) ~= v
      b[1]:SetEnabled(on)
      b[1]:SetAlpha(on and 1 or 0.35)
    end
  end
  registry[#registry + 1] = s
  return s
end

-- the next entry of a list of values
local function InList(list)
  return function(v, dir)
    for i, x in ipairs(list) do
      if x == v then return list[math.max(1, math.min(#list, i + dir))] end
    end
    return list[1]
  end
end

-- a section header: white text with the game's divider under it, `width` wide
local function Header(parent, text, width)
  local fs = Label(parent, text, _G.GameFontHighlightMedium and "GameFontHighlightMedium" or "GameFontHighlight")
  local line = Skin.Divider(parent)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
  line:SetWidth(width)
  fs.line = line
  return fs
end

-- a flat button: dropdown bodies and list rows
local function PlainButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h or 22)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.12)
  b:SetNormalFontObject("GameFontHighlightSmall")
  b:SetHighlightFontObject("GameFontHighlightSmall")
  b:SetDisabledFontObject("GameFontDisableSmall")
  b:SetText(text)
  FitWidth(b, w)
  return b
end

-- a dropdown like the game's: a field that opens a list below it. dd.Select(value) is what a
-- click on a list row does (also used by the tests)
local function Dropdown(parent, width, entries, getText, onPick)
  local dd = PlainButton(parent, " ", width)
  dd:SetWidth(width)
  Skin.Field(dd)
  local fs = dd:GetFontString()
  if fs then
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", 10, 0)
    fs:SetPoint("RIGHT", -24, 0)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
  end
  if not Skin.DropArrow(dd) then
    local arrow = dd:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetRotation(-math.pi / 2)
  end
  local list = CreateFrame("Frame", nil, dd)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetPoint("BOTTOMRIGHT", dd, "TOPRIGHT", 0, 2) -- it sits in the footer: the list opens upwards
  list:SetClampedToScreen(true)
  list:EnableMouse(true)
  local lbg = list:CreateTexture(nil, "BACKGROUND")
  lbg:SetAllPoints()
  lbg:SetColorTexture(Skin.BG[1], Skin.BG[2], Skin.BG[3], 0.98)
  Skin.Edge(list, Skin.EDGE, 1)
  list:Hide()
  function dd.Select(value)
    list:Hide()
    onPick(value)
  end
  local rows, maxW = {}, width
  for i, e in ipairs(entries) do
    local r = PlainButton(list, e.text, width, 20)
    local rfs = r:GetFontString()
    if rfs then
      rfs:ClearAllPoints()
      rfs:SetPoint("LEFT", 10, 0)
    end
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2 - (i - 1) * 21)
    r:SetScript("OnClick", function() dd.Select(e.value) end)
    maxW = math.max(maxW, r:GetWidth() or width)
    rows[i] = r
  end
  for _, r in ipairs(rows) do r:SetWidth(maxW) end
  list:SetSize(maxW + 4, #entries * 21 + 3)
  dd.list, dd.rows = list, rows
  dd:SetScript("OnClick", function()
    if list:IsShown() then list:Hide() return end
    if openList and openList ~= list then openList:Hide() end
    openList = list
    list:Show()
  end)
  dd:SetScript("OnHide", function() list:Hide() end)
  dd.Refresh = function() dd:SetText(getText()) end
  registry[#registry + 1] = dd
  return dd
end

-- Esc closes the window (the game looks the name up in UISpecialFrames)
local function EscListed(frame, name)
  if _G[name] ~= frame then _G[name] = frame end
  if not UISpecialFrames then return end
  for _, n in ipairs(UISpecialFrames) do if n == name then return end end
  table.insert(UISpecialFrames, name)
end

local Build
-- a new language: the window is built anew in it (and opened again where it was)
local function LanguageChanged(code)
  local db = ns.db
  if code == db.language then return end
  db.language = code
  ns.SetLanguage(code)
  if ns.OnLanguageChanged then ns.OnLanguageChanged() end
  local wasShown = win and win:IsShown()
  if win then win:Hide() end
  win = nil
  Build()
  ns.RefreshOptions()
  if wasShown then win:Show() end
end

-- the window: a title band, "Target | Focus" in two columns with the same rows at the same
-- heights, and a footer across both (language, unlock, reset), as in Full Mana Forever
Build = function()
  local db = ns.db
  registry = {}
  win = CreateFrame("Frame", nil, UIParent)
  win:SetSize(W, 400)
  -- its own place, kept for the account; the first time at the right edge of the screen
  local op = db.optPoint
  if op then
    win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", op[1], op[2])
  else
    win:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
  end
  win:SetFrameStrata("DIALOG")
  if win.SetToplevel then win:SetToplevel(true) end
  win:EnableMouse(true)
  win:SetMovable(true)
  win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local l, t = self:GetLeft(), self:GetTop()
    if l and t then db.optPoint = { l, t } end
  end)
  win:Hide()
  EscListed(win, "LastBreathForeverOptions")
  Skin.Window(win, 0, { portrait = Skin.LOGO })

  local title = Label(win, "Last Breath Forever  |cff888888v" .. ns.VERSION .. "|r", "GameFontNormalLarge")
  Skin.PlaceTitle(title, win, PAD)
  local close = Skin.Close(win)
  if not close then
    close = CreateFrame("Button", nil, win)
    close:SetSize(22, 22)
    close:SetNormalFontObject("GameFontHighlightSmall")
    close:SetText("X")
  end
  Skin.PlaceClose(close, win)
  close:SetScript("OnClick", function() win:Hide() end)
  Tip(close, L.optClose, L.tipClose)
  win.close = close

  local top = Skin.ContentTop(win) - 6
  local IN = 4 -- rows sit a little right of their header, like the game's settings
  win.controls = { close }
  local function control(...)
    for _, c in ipairs({ ... }) do win.controls[#win.controls + 1] = c end
  end

  -- the five settings of one frame, the same rows in both columns. cfg() = the table they
  -- are read and written; enabledIf() false greys them out
  local function Column(x, y, cfg, enabledIf, changed, plates)
    local function at(widget, dy)
      widget:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
      y = y - (dy or ROW)
    end
    local size = Stepper(win, L.optSize, L.tipSize,
      function() return cfg().scale end,
      function(v) cfg().scale = v; changed() end,
      { fmt = function(v) return string.format("%d %%", math.floor(v * 100 + 0.5)) end,
        next = function(v, dir) return math.max(0.5, math.min(3, math.floor((v + dir * 0.1) * 10 + 0.5) / 10)) end },
      enabledIf)
    at(size.label)
    -- above nameplates: only up to 1:30 (their own list; the target's when they follow it)
    local limit = Stepper(win, L.optLimit, plates and L.tipPlateLimit or L.tipLimit,
      function() return cfg().limit end,
      function(v) cfg().limit = v end,
      { fmt = function(v) return v == 0 and L.optAlways or string.format(L.fmtSecShort, v) end,
        next = function(v, dir)
          local list = (plates and cfg() == db.p) and ns.PLATE_LIMITS or ns.LIMITS
          return InList(list)(v, dir)
        end },
      enabledIf)
    at(limit.label)
    local urgent = Stepper(win, L.optUrgent, L.tipUrgent,
      function() return cfg().urgent end,
      function(v) cfg().urgent = v end,
      { fmt = function(v) return v == 0 and L.optOff or string.format(L.fmtSecShort, v) end, next = InList(ns.URGENTS) },
      enabledIf)
    at(urgent.label)
    local icon = Check(win, L.optIcon, L.tipIcon, function() return cfg().icon end,
      function(v) cfg().icon = v; changed() end, enabledIf)
    at(icon, 28)
    local elite = Check(win, L.optElite, L.tipElite, function() return cfg().elite end,
      function(v) cfg().elite = v end, enabledIf)
    at(elite, 28)
    local list = { size.minus, size.plus, size.tipArea, limit.minus, limit.plus, limit.tipArea,
      urgent.minus, urgent.plus, urgent.tipArea, icon, elite }
    control(unpack(list))
    return y, list
  end

  local LX, RX, PX = PAD, COL + PAD, 2 * COL + PAD
  local introY = top - 30
  local rowsY = introY - 84

  -- left: the target
  local h1 = Header(win, L.optTarget, COL - 2 * PAD)
  h1:SetPoint("TOPLEFT", win, "TOPLEFT", LX, top)
  local intro = Label(win, L.noteTarget, "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT", win, "TOPLEFT", LX + IN, introY - 6)
  intro:SetWidth(COL - 2 * PAD - IN)
  local y, leftRows = Column(LX + IN, rowsY, function() return db end, nil, ns.Apply)

  -- right: the focus. Two switches, then the same rows: the target's values greyed out while
  -- the focus follows them, its own otherwise
  local h2 = Header(win, L.hudFocus, COL - 2 * PAD)
  h2:SetPoint("TOPLEFT", win, "TOPLEFT", RX, top)
  local show = Check(win, L.optFocus, L.tipFocus, function() return db.focus end,
    function(v) db.focus = v; ns.Apply() end)
  show:SetPoint("TOPLEFT", win, "TOPLEFT", RX + IN, introY)
  local sameAs = Check(win, L.optSame, L.tipSame, function() return db.focusSame end,
    function(v) db.focusSame = v; ns.Apply() end, function() return db.focus end)
  sameAs:SetPoint("TOPLEFT", win, "TOPLEFT", RX + IN, introY - 26)
  control(show, sameAs)
  local _, rightRows = Column(RX + IN, rowsY, function() return db.focusSame and db or db.f end,
    function() return db.focus and not db.focusSame end, ns.Apply)

  -- third column: the nameplates. Seconds above every enemy's nameplate (also the target's and
  -- the focus's: the same enemy shows the same number everywhere), following enemies by them
  local h3 = Header(win, L.optPlatesHead, COL - 2 * PAD)
  h3:SetPoint("TOPLEFT", win, "TOPLEFT", PX, top)
  local plates = Check(win, L.optPlates, L.tipPlates, function() return db.plates end,
    function(v) db.plates = v; ns.Apply() end)
  plates:SetPoint("TOPLEFT", win, "TOPLEFT", PX + IN, introY)
  local allPlates = Check(win, L.optAllPlates, L.tipAllPlates, function() return db.allPlates end,
    function(v) db.allPlates = v; ns.Apply() end, function() return db.plates end)
  allPlates:SetPoint("TOPLEFT", win, "TOPLEFT", PX + IN, introY - 26)
  local plateSame = Check(win, L.optSame, L.tipSamePlates, function() return db.plateSame end,
    function(v) db.plateSame = v; ns.Apply() end, function() return db.plates and db.allPlates end)
  plateSame:SetPoint("TOPLEFT", win, "TOPLEFT", PX + IN, introY - 52)
  control(plates, allPlates, plateSame)
  local py, plateRows = Column(PX + IN, rowsY, function() return db.plateSame and db or db.p end,
    function() return db.plates and db.allPlates and not db.plateSame end, ns.Apply, true)
  -- a sixth row only here: how high above the nameplate
  local plateY = Stepper(win, L.optPlateY, L.tipPlateY,
    function() return db.plateY end,
    function(v) db.plateY = v; ns.Apply() end,
    { fmt = function(v) return string.format("%+d", v) end,
      next = function(v, dir) return math.max(-20, math.min(60, v + dir * 2)) end },
    function() return db.plates and db.allPlates end)
  plateY.label:SetPoint("TOPLEFT", win, "TOPLEFT", PX + IN, py)
  py = py - ROW
  control(plateY.minus, plateY.plus, plateY.tipArea)
  y = math.min(y, py)

  -- what the seconds are, across both columns
  y = y - 4
  local note = Label(win, L.optNote, "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", win, "TOPLEFT", LX + IN, y)
  note:SetWidth(W - 2 * PAD - IN)
  note:SetTextColor(GREY[1] + 0.2, GREY[2] + 0.2, GREY[3] + 0.2)
  local noteH = note.GetStringHeight and note:GetStringHeight() or 0
  if type(noteH) ~= "number" or noteH < 24 then noteH = 24 end
  y = y - noteH - 12

  -- the line between the columns, from under the headers down to the footer line
  local sep = win:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(Skin.EDGE[1], Skin.EDGE[2], Skin.EDGE[3], 0.6)
  sep:SetWidth(1)
  sep:SetPoint("TOP", win, "TOPLEFT", COL, top - 22)
  sep:SetPoint("BOTTOM", win, "TOPLEFT", COL, y + noteH + 16)
  local sep2 = win:CreateTexture(nil, "ARTWORK")
  sep2:SetColorTexture(Skin.EDGE[1], Skin.EDGE[2], Skin.EDGE[3], 0.6)
  sep2:SetWidth(1)
  sep2:SetPoint("TOP", win, "TOPLEFT", 2 * COL, top - 22)
  sep2:SetPoint("BOTTOM", win, "TOPLEFT", 2 * COL, y + noteH + 16)

  -- footer across both columns: the language (left), placing the frames (right)
  local fline = win:CreateTexture(nil, "ARTWORK")
  fline:SetColorTexture(Skin.EDGE[1], Skin.EDGE[2], Skin.EDGE[3], 0.6)
  fline:SetHeight(1)
  fline:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
  fline:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, y)
  y = y - 14
  local langLabel = Label(win, L.optLang .. ":")
  langLabel:SetPoint("TOPLEFT", win, "TOPLEFT", LX + IN, y - 4)
  local entries = { { value = "auto", text = L.langAuto .. " (" .. ns.LanguageName(ns.GameLanguage()) .. ")" } }
  for _, l in ipairs(ns.LANGUAGES) do entries[#entries + 1] = { value = l.code, text = l.name } end
  local lang = Dropdown(win, 200, entries, function()
    if db.language == "auto" then return L.langAuto end
    return ns.LanguageName(db.language, true)
  end, LanguageChanged)
  lang:SetPoint("LEFT", langLabel, "LEFT", 90, 0)
  Tip(lang, L.optLang, L.tipLang)
  local langTip = TipArea(win, langLabel, L.optLang, L.tipLang)
  local reset = Button(win, L.optResetPos, 150)
  reset:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, y)
  reset:SetScript("OnClick", function() ns.ResetPosition() end)
  Tip(reset, L.optResetPos, L.tipResetPos)
  local lock = Button(win, L.optUnlock, 150)
  lock:SetPoint("RIGHT", reset, "LEFT", -8, 0)
  lock:SetScript("OnClick", function() ns.SetLocked(not db.locked, true) end)
  Tip(lock, L.optUnlock, L.tipUnlock)
  lock.Refresh = function()
    lock:SetText(db.locked and L.optUnlock or L.optLock)
    FitWidth(lock, 150)
  end
  registry[#registry + 1] = lock
  control(lang, langTip, lock, reset)
  win:SetHeight(-(y - 22 - 16))
  win.widgets = { show = show, sameAs = sameAs, lang = lang, lock = lock, reset = reset,
    plates = plates, allPlates = allPlates, plateSame = plateSame, plateRows = plateRows, plateY = plateY,
    leftRows = leftRows, rightRows = rightRows }
  ns.optionsWindow = win
end

function ns.RefreshOptions()
  if not win then return end
  for _, r in ipairs(registry) do r.Refresh() end
end

function ns.ToggleOptions(forceShow)
  if not win then Build() end
  if win:IsShown() and not forceShow then
    win:Hide()
  else
    EscListed(win, "LastBreathForeverOptions")
    ns.RefreshOptions()
    win:Show()
  end
end

function ns.InitOptions() end
