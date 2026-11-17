-- Last Breath Forever - the settings window. Plain frames in the look of the series (Skin.lua).

local _, ns = ...
local L = ns.L
local Skin = ns.Skin
local GREY = Skin.GREY

local W, PAD, ROW = 400, 18, 30
local VALUE_X = 230 -- where the values of the steppers start
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

local function Check(parent, text, tip, get, set)
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
  cb.Refresh = function() cb:SetChecked(get() and true or false) end
  registry[#registry + 1] = cb
  return cb
end

-- "Label:   ◄ [ value ] ►"; o.next(v, dir) gives the next value (the same one at the end)
local function Stepper(parent, text, tip, get, set, o)
  local s = {}
  s.label = Label(parent, text .. ":")
  s.minus = ArrowButton(parent, -1)
  s.minus:SetPoint("LEFT", s.label, "LEFT", VALUE_X - PAD, 0)
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
    -- a button that would change nothing is greyed out
    for _, b in ipairs({ { s.minus, -1 }, { s.plus, 1 } }) do
      local on = o.next(v, b[2]) ~= v
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
  line:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
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
  win:SetSize(W, 392)
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

  local y = Skin.ContentTop(win) - 6
  local function place(widget, dy)
    widget:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
    y = y - (dy or ROW)
  end

  place(Header(win, L.optDisplay), 30)
  local size = Stepper(win, L.optSize, L.tipSize,
    function() return db.scale end,
    function(v) db.scale = v; ns.Apply() end,
    { fmt = function(v) return string.format("%d %%", math.floor(v * 100 + 0.5)) end,
      next = function(v, dir) return math.max(0.5, math.min(3, math.floor((v + dir * 0.1) * 10 + 0.5) / 10)) end })
  place(size.label)
  local limit = Stepper(win, L.optLimit, L.tipLimit,
    function() return db.limit end,
    function(v) db.limit = v end,
    { fmt = function(v) return v == 0 and L.optAlways or string.format(L.fmtSecShort, v) end, next = InList(ns.LIMITS) })
  place(limit.label)
  local urgent = Stepper(win, L.optUrgent, L.tipUrgent,
    function() return db.urgent end,
    function(v) db.urgent = v end,
    { fmt = function(v) return v == 0 and L.optOff or string.format(L.fmtSecShort, v) end, next = InList(ns.URGENTS) })
  place(urgent.label)
  place(Check(win, L.optIcon, L.tipIcon, function() return db.icon end, function(v) db.icon = v; ns.Apply() end), 28)
  place(Check(win, L.optElite, L.tipElite, function() return db.elite end, function(v) db.elite = v end), 40)

  place(Header(win, L.optPosition), 32)
  local lock = Button(win, L.optUnlock, 120)
  place(lock, 0)
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
  y = y - 38

  local note = Label(win, L.optNote, "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
  note:SetWidth(W - 2 * PAD)
  note:SetTextColor(GREY[1] + 0.2, GREY[2] + 0.2, GREY[3] + 0.2)

  win.controls = { close, size.minus, size.plus, size.tipArea, limit.minus, limit.plus, limit.tipArea,
    urgent.minus, urgent.plus, urgent.tipArea, lock, reset }
  for _, r in ipairs(registry) do if r.tipTitle then win.controls[#win.controls + 1] = r end end
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
