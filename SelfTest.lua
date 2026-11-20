-- /lbf selftest: every setting in turn for a moment, in the real game, and a list of the errors
-- with the setting they came from. The player's settings are kept aside and come back at the end
-- (also after a /reload in the middle). The texts are technical and in English, for bug reports.
local _, ns = ...

do
  local STEP = 0.5 -- seconds per step: a full update of the seconds and a few frames
  -- what a step may change (unlocking the frames is left out: it moves things under the mouse)
  local KEYS = { "scale", "icon", "limit", "urgent", "elite", "focus", "focusSame", "plates",
    "allPlates", "plateSame", "plateY", "language" }
  -- settings no step changes, on purpose
  local SKIP = { locked = true }
  ns.SELFTEST_KEYS, ns.SELFTEST_SKIP = KEYS, SKIP
  local NIL = "__nil"

  local function Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = Copy(v) end
    return c
  end

  local function Save(db)
    local b = {}
    for _, k in ipairs(KEYS) do
      if db[k] == nil then b[k] = NIL else b[k] = db[k] end
    end
    b.f, b.p = Copy(db.f), Copy(db.p)
    return b
  end

  local function Restore(db, b)
    for k, v in pairs(b) do
      if k == "f" or k == "p" then db[k] = Copy(v)
      elseif v == NIL then db[k] = nil
      else db[k] = v end
    end
  end

  -- the list of steps: a name and what it sets
  local function Steps()
    local steps = {}
    local function add(name, fn) steps[#steps + 1] = { name = name, fn = fn } end
    -- the five settings of one frame; on() makes that frame show with its own settings
    local function frame(prefix, cfg, on, limits)
      add(prefix .. ".scale=0.5", function(db) on(db) cfg(db).scale = 0.5 end)
      add(prefix .. ".scale=3", function(db) on(db) cfg(db).scale = 3 end)
      add(prefix .. ".icon flipped", function(db) on(db) cfg(db).icon = not cfg(db).icon end)
      add(prefix .. ".elite flipped", function(db) on(db) cfg(db).elite = not cfg(db).elite end)
      for _, v in ipairs(limits) do
        add(prefix .. ".limit=" .. v, function(db) on(db) cfg(db).limit = v end)
      end
      for _, v in ipairs(ns.URGENTS) do
        add(prefix .. ".urgent=" .. v, function(db) on(db) cfg(db).urgent = v end)
      end
    end
    frame("target", function(db) return db end, function() end, ns.LIMITS)
    frame("focus", function(db) return db.f end,
      function(db) db.focus, db.focusSame = true, false end, ns.LIMITS)
    frame("plates", function(db) return db.p end,
      function(db) db.plates, db.allPlates, db.plateSame = true, true, false end, ns.PLATE_LIMITS)
    for _, k in ipairs({ "focus", "focusSame", "plates", "allPlates", "plateSame" }) do
      add(k .. " flipped", function(db) db[k] = not db[k] end)
    end
    add("plateY=-20", function(db) db.plates, db.allPlates, db.plateY = true, true, -20 end)
    add("plateY=60", function(db) db.plates, db.allPlates, db.plateY = true, true, 60 end)
    for _, l in ipairs(ns.LANGUAGES) do
      add("language=" .. l.code, function(db) db.language = l.code end)
    end
    -- where trouble is most likely: everything on at once, at the ends of the ranges
    local function all(db, own)
      db.focus, db.plates, db.allPlates = true, true, true
      db.focusSame, db.plateSame = not own, not own
    end
    add("all frames smallest, always, red 60 s", function(db)
      all(db, true)
      for _, c in ipairs({ db, db.f, db.p }) do c.scale, c.icon, c.urgent = 0.5, false, 60 end
      db.limit, db.f.limit, db.p.limit = 0, 0, 90
    end)
    add("all frames biggest, icons, 10 min", function(db)
      all(db, true)
      for _, c in ipairs({ db, db.f, db.p }) do c.scale, c.icon, c.urgent = 3, true, 5 end
      db.limit, db.f.limit, db.p.limit = 600, 600, 30
    end)
    add("focus and nameplates follow the target, always", function(db)
      all(db, false)
      db.limit, db.urgent = 0, 60
    end)
    add("only elites and bosses everywhere", function(db)
      all(db, true)
      db.elite, db.f.elite, db.p.elite = true, true, true
    end)
    add("nameplates counted but not shown", function(db)
      db.plates, db.allPlates = true, false
    end)
    return steps
  end

  ns.SelfTestSteps = Steps

  local run -- the running test, or nil

  local function Language(db)
    ns.SetLanguage(db.language)
    if ns.OnLanguageChanged then ns.OnLanguageChanged() else ns.Apply() end
  end

  local function Note(msg)
    if not run then return end
    local line = run.steps[run.i] and run.steps[run.i].name or "start"
    line = line .. ": " .. tostring(msg)
    if not run.seen[line] then
      run.seen[line] = true
      run.errors[#run.errors + 1] = line
    end
  end

  local function Finish(stopped)
    local db = ns.db
    ns.selfTestNote = nil
    if run.oldHandler and seterrorhandler then seterrorhandler(run.oldHandler) end
    Restore(db, db.selftestBackup)
    db.selftestBackup = nil
    pcall(Language, db)
    if ns.ForceCycle then ns.ForceCycle() end
    if ns.RefreshOptions then pcall(ns.RefreshOptions) end
    local done, total = run.i - 1, #run.steps
    if done > total then done = total end
    local where = run.combat and "in combat" or "out of combat"
    local secs = math.floor(GetTime() - run.start + 0.5)
    local errors = run.errors
    run = nil
    if stopped then
      ns.Print("self-test stopped: %d of %d settings in %d s (%s), your settings are back.", done, total, secs, where)
    else
      ns.Print("self-test done: %d of %d settings in %d s (%s), your settings are back.%s", done, total, secs,
        where, #errors == 0 and " No errors." or "")
    end
    for _, e in ipairs(errors) do DEFAULT_CHAT_FRAME:AddMessage(e) end
    if #errors > 0 then ns.BugLink() end
  end

  local function Next()
    if not run then return end
    local db = ns.db
    run.i = run.i + 1
    local step = run.steps[run.i]
    if not step then return Finish(false) end
    if run.i > 1 and (run.i - 1) % 10 == 0 then
      ns.Print("self-test: %d of %d ...", run.i - 1, #run.steps)
    end
    -- back to the player's settings, then this step's values on top
    Restore(db, db.selftestBackup)
    local ok, err = pcall(step.fn, db)
    if ok then ok, err = pcall(Language, db) end
    if not ok then Note(err) end
    if ns.ForceCycle then ns.ForceCycle() end
    C_Timer.After(STEP, Next)
  end

  function ns.SelfTest(stop)
    if stop then
      if run then Finish(true) else ns.Print("self-test is not running.") end
      return
    end
    if run then ns.Print("self-test is already running (/lbf selftest stop).") return end
    local db = ns.db
    db.selftestBackup = Save(db)
    run = { steps = Steps(), i = 0, errors = {}, seen = {}, start = GetTime(),
      combat = InCombatLockdown and InCombatLockdown() == true }
    ns.selfTestNote = Note
    -- errors outside the addon's own checks (scripts of frames) go into the list too
    if geterrorhandler and seterrorhandler then
      run.oldHandler = geterrorhandler()
      seterrorhandler(function(e) Note(e) end)
    end
    ns.Print("self-test: %d settings, about %d s. Your settings come back at the end.", #run.steps,
      math.ceil(#run.steps * STEP))
    Next()
  end

  -- a test cut off by a /reload or logout: the player's settings come back at the next login
  function ns.SelfTestRecover()
    local db = ns.db
    if run or not db or type(db.selftestBackup) ~= "table" then return end
    Restore(db, db.selftestBackup)
    db.selftestBackup = nil
    pcall(Language, db)
    ns.Print("self-test was cut off: your settings are back.")
  end

  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" and ns.db then ns.SelfTestRecover() end
  end)
  pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
end
