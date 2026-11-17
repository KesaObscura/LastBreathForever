-- Last Breath Forever - the settings window. Plain frames in the look of the series (Skin.lua).

local _, ns = ...
local L = ns.L
local Skin = ns.Skin
local GOLD, GREY = Skin.GOLD, Skin.GREY

local COL, PAD, ROW = 370, 18, 30   -- two columns: target | focus
local W = 2 * COL
local VALUE_X = 214 -- where the values of the steppers start, from the label's left edge
local win
local registry = {} -- everything with a Refresh

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

local function Header(parent, text)
  local fs = Label(parent, text, _G.GameFontHighlightMedium and "GameFontHighlightMedium" or "GameFontHighlight")
  local line = Skin.Divider(parent)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
  fs.line = line
  return fs
end

-- Esc closes the window (the game looks the name up in UISpecialFrames)
local function EscListed(frame, name)
  if _G[name] ~= frame then _G[name] = frame end
  if not UISpecialFrames then return end
  for _, n in ipairs(UISpecialFrames) do if n == name then return end end
  table.insert(UISpecialFrames, name)
end

local function Build()
  local db = ns.db
  win = CreateFrame("Frame", nil, UIParent)
  win:SetSize(W, 400)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:EnableMouse(true)
  win:SetMovable(true)
  win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
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
  win.controls = { close }
  local function control(...)
    for _, c in ipairs({ ... }) do win.controls[#win.controls + 1] = c end
  end

  -- the five settings of one frame, the same rows in both columns. cfg() = the table they
  -- are read from, own() = the table they are written to (nil: greyed out)
  local function Column(x, y, cfg, enabledIf, changed)
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
    local limit = Stepper(win, L.optLimit, L.tipLimit,
      function() return cfg().limit end,
      function(v) cfg().limit = v end,
      { fmt = function(v) return v == 0 and L.optAlways or string.format(L.fmtSecShort, v) end, next = InList(ns.LIMITS) },
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
    control(size.minus, size.plus, size.tipArea, limit.minus, limit.plus, limit.tipArea,
      urgent.minus, urgent.plus, urgent.tipArea, icon, elite)
    return y
  end

  local function header(text, x)
    local h = Header(win, text)
    h:SetPoint("TOPLEFT", win, "TOPLEFT", x, top)
    h.line:SetPoint("RIGHT", win, "TOPLEFT", x + COL - 2 * PAD, 0)
  end
  local LX, RX = PAD, COL + PAD
  local introY, rowsY = top - 30, top - 30 - 58

  -- left: the target
  header(L.optTarget, LX)
  local intro = Label(win, L.noteTarget, "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT", win, "TOPLEFT", LX, introY - 6)
  intro:SetWidth(COL - 2 * PAD)
  local y = Column(LX, rowsY, function() return db end, nil, ns.Apply)

  -- right: the focus. Two switches, then the same rows: the target's values greyed out while
  -- the focus follows them, its own otherwise
  header(L.hudFocus, RX)
  local show = Check(win, L.optFocus, L.tipFocus, function() return db.focus end,
    function(v) db.focus = v; ns.Apply() end)
  show:SetPoint("TOPLEFT", win, "TOPLEFT", RX, introY)
  local sameAs = Check(win, L.optSame, L.tipSame, function() return db.focusSame end,
    function(v) db.focusSame = v; ns.Apply() end, function() return db.focus end)
  sameAs:SetPoint("TOPLEFT", win, "TOPLEFT", RX, introY - 26)
  control(show, sameAs)
  Column(RX, rowsY, function() return db.focusSame and db or db.f end,
    function() return db.focus and not db.focusSame end, ns.Apply)

  -- a thin line between the columns
  local sep = win:CreateTexture(nil, "ARTWORK")
  sep:SetWidth(1)
  sep:SetPoint("TOP", win, "TOPLEFT", COL, top + 2)
  sep:SetPoint("BOTTOM", win, "TOPLEFT", COL, y + 14)
  sep:SetColorTexture(Skin.EDGE[1], Skin.EDGE[2], Skin.EDGE[3], 0.6)

  -- below both: where the frames stand, and what the seconds are
  y = y - 8
  local pos = Header(win, L.optPosition)
  pos:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
  pos.line:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)
  y = y - 32
  local lock = Button(win, L.optUnlock, 120)
  lock:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
  lock:SetScript("OnClick", function() ns.SetLocked(not db.locked, true) end)
  Tip(lock, L.optUnlock, L.tipUnlock)
  lock.Refresh = function()
    lock:SetText(db.locked and L.optUnlock or L.optLock)
    FitWidth(lock, 120)
  end
  registry[#registry + 1] = lock
  local reset = Button(win, L.optResetPos, 120)
  reset:SetPoint("LEFT", lock, "RIGHT", 8, 0)
  reset:SetScript("OnClick", function() ns.ResetPosition() end)
  Tip(reset, L.optResetPos, L.tipResetPos)
  control(lock, reset)
  local note = Label(win, L.optNote, "GameFontDisableSmall")
  note:SetPoint("LEFT", reset, "RIGHT", 16, 0)
  note:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)
  note:SetTextColor(GREY[1] + 0.2, GREY[2] + 0.2, GREY[3] + 0.2)
  win:SetHeight(-(y - 22 - 24))
  win.widgets = { show = show, sameAs = sameAs }
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
