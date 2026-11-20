-- /gcc debug: an in-game test suite. It puts each look on the real crosshair, one
-- step every Debug.SECONDS_PER_STEP, checks what the game shows (our textures'
-- size, color and picture, the game's dot hidden or back), puts your own settings
-- back, and keeps the findings in GamepadCrosshairCustomizerDebugDB (written to
-- disk on /reload). Not in the release zip (.pkgmeta).
--   /gcc debug         runs the whole suite (out of combat, controller UI on)
--   /gcc friendly      runs only its friendly player part, then the target cleared
--   /gcc monsters      runs only its neutral and enemy NPC part, then the target cleared
--   (by hand: select the targets yourself when the corner says so)
--   /gcc debug last    prints the last run's findings again
--   /gcc debug clear   empties the saved runs
-- A fight stops the run; a reload during one puts your settings back at login.
--
-- Its parts:
--   1. the crosshair with no target;
--   2. the icons on a real friendly player target, then its class icon on more
--      friendly players of other classes nearby (optional, up to
--      MORE_CLASSES), each checked against the class color its nameplate shows;
--   3. once you've moved near one, a neutral or enemy NPC (a class icon must
--      leave the crosshair as it is there), and the other of the two if one is
--      in range too (optional);
--   4. the crosshair back once the target is cleared.
-- Addon code can't select or clear a target, so the run waits for one, and keys
-- do it from outside, through secure macro buttons (as the reload box's Reload):
-- TARGET_KEY (/targetfriendplayer, else yourself; again: the next one),
-- TARGET_ENEMY_KEY (/targetenemy: attackable units, neutral ones too) and
-- CLEAR_TARGET_KEY (/cleartarget). By hand, select them yourself when the corner
-- says so. An enemy that pulls you into a fight stops the run.
--
-- Screenshots: tests/screenshot_debug.sh (outside the game) starts the run with
-- START_KEY, presses the target keys when asked, and shoots each step. The square
-- in the top-left corner says what's on screen:
--   green    a step, its number in the blue (step x MARKER_BLUE_PER_STEP / 255)
--   yellow   waiting for the crosshair (touch the controller)
--   blue     waiting for a friendly player target
--   navy     waiting for no target
--   violet   waiting for a neutral or enemy NPC (move near one), or the other kind
--   red      the run stopped; gone: done
-- Each step's crosshair position on screen (screen pixels from the top-left) is
-- saved with the run, for the crops.
local addon = _G.GamepadCrosshairCustomizer
local Debug = { SECONDS_PER_STEP = 2.5, RUNS_KEPT = 10, MARKER_BLUE_PER_STEP = 8,
    -- Keys from outside reach the game; typing in its chat isn't tried. Free among
    -- the dev tools' keys.
    START_KEY = "ALT-CTRL-SHIFT-C", TARGET_KEY = "ALT-CTRL-SHIFT-Y", CLEAR_TARGET_KEY = "ALT-CTRL-SHIFT-X",
    TARGET_ENEMY_KEY = "ALT-CTRL-SHIFT-Z",
    TARGET_MACRO = "/targetfriendplayer\n/target [noexists] player",
    -- The game hides its crosshair while the cursor shows, and after a reload the
    -- controller UI only comes back with the controller's first input: the run
    -- waits for it (and for each target change) up to WAIT_SECONDS. (It doesn't
    -- switch the controller UI on itself: InputDeviceInterfaceStyle switches the
    -- whole interface, and from addon code that would run the game's switch tainted.)
    WAIT_SECONDS = 60, POLL_SECONDS = 0.5,
    MORE_CLASSES = 4,                 -- friendly players of other classes looked for
    OPTIONAL_WAIT_SECONDS = 12,       -- how long each optional target is looked for
    NPC_WAIT_SECONDS = 180,           -- time to walk near a neutral or enemy NPC
    CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK",
        "MONK", "DRUID", "DEMONHUNTER", "EVOKER" },
}
addon.Debug = Debug

local function say(text) print("|cff88ccffgcc debug|r " .. text) end

-- Saved findings and the settings to put back

local function getDebugStore()
    if type(GamepadCrosshairCustomizerDebugDB) ~= "table" then GamepadCrosshairCustomizerDebugDB = {} end
    local debugStore = GamepadCrosshairCustomizerDebugDB
    if type(debugStore.runs) ~= "table" then debugStore.runs = {} end
    return debugStore
end

local function copyCurrentSettings()
    local settings, copy = addon.Settings(), {}
    for key in pairs(addon.DEFAULTS) do copy[key] = settings[key] end
    return copy
end

local function restoreSettings(savedCopy)
    local settings = addon.Settings()
    for key in pairs(addon.DEFAULTS) do
        if savedCopy[key] ~= nil then settings[key] = savedCopy[key] end
    end
    addon.UpdateCrosshair()
end

-- Checks

local currentRun   -- the run in progress, or nil

local function recordCheck(name, passed, expected, actual, note)
    local result = (passed == nil and "skip") or (passed and "pass") or "fail"
    currentRun.checks[#currentRun.checks + 1] = { name = name, result = result,
        expected = expected ~= nil and tostring(expected) or nil, actual = actual ~= nil and tostring(actual) or nil,
        note = note }
end
local function expectEqual(name, expected, actual) recordCheck(name, tostring(actual) == tostring(expected), expected, actual) end
local function expectNear(name, expected, actual, tolerance)
    local actualNumber = tonumber(actual)
    recordCheck(name, actualNumber ~= nil and math.abs(actualNumber - expected) <= (tolerance or 0.01), expected, actual)
end
local function skipCheck(name, reason) recordCheck(name, nil, nil, nil, reason) end

-- A texture's file as the game reports it, for comparing: a probe texture is
-- given the same path, so both read back the same way (a file id or a path).
local probe
local function fileAsGameReportsIt(path)
    if not probe then probe = CreateFrame("Frame"):CreateTexture() end
    probe:SetTexture(path)
    return probe:GetTexture()
end

local function gameDot()
    local crosshairFrame = _G.GamepadReticle
    return type(crosshairFrame) == "table" and crosshairFrame.Icons and crosshairFrame.Icons.StandardIcon or nil
end

local function colorText(region) return addon.FormatColor(region:GetVertexColor()) end

-- Where the crosshair is on screen, in screen pixels from the top-left, and its
-- width there; nil when it can't be measured (on a nameplate: a restricted region).
local function crosshairOnScreen(region)
    local succeeded, x, y = pcall(region.GetCenter, region)
    if not (succeeded and x and y) or type(GetPhysicalScreenSize) ~= "function" then return nil end
    local screenWidth, screenHeight = GetPhysicalScreenSize()
    local pixelsPerUnit = screenHeight / (UIParent:GetHeight() * UIParent:GetEffectiveScale()) * region:GetEffectiveScale()
    return { x = math.floor(x * pixelsPerUnit + 0.5), y = math.floor(screenHeight - y * pixelsPerUnit + 0.5),
        width = math.floor(region:GetWidth() * pixelsPerUnit + 0.5), screenWidth = screenWidth, screenHeight = screenHeight }
end

-- What a step should show, worked out from its own look and the real target (not
-- from the addon's choice): { icon, texture or atlas, size, tinted }.
local function expectedLook(step, settings)
    local target = addon.TargetInfo()
    if step.shows == "targetIcon" and not target.hasNameplate then
        -- No nameplate on screen for this target: the crosshair stays (checked as such).
        local icon = settings.icon
        return { icon = icon, texture = addon.Icons.Texture(icon), size = settings.size, tinted = true }
    end
    if step.shows == "targetIcon" then
        if settings.targetIcon == "class" then
            -- In its style: the game's atlas, or a JiberishUI sheet's cell (the game's without it).
            local classLook = addon.Icons.ClassLook(target.classFile, settings.classStyle) or {}
            return { icon = "class", atlas = classLook.atlas, texture = classLook.texture, texCoord = classLook.texCoord,
                size = settings.iconSize, tinted = false }
        end
        return { icon = settings.targetIcon, texture = addon.Icons.Texture(settings.targetIcon, settings.customTexture),
            size = settings.iconSize, tinted = false }
    end
    local icon = settings.icon
    if step.needsJiberish and not addon.Icons.JiberishInstalled() then icon = "dot" end
    return { icon = icon, texture = addon.Icons.Texture(icon), size = settings.size, tinted = true }
end

-- Applies a step's look, then checks the game shows what it should.
local function checkLook(label, step)
    local settings = addon.Settings()
    for key, value in pairs(addon.DEFAULTS) do settings[key] = value end
    for key, value in pairs(step.look) do settings[key] = value end
    addon.UpdateCrosshair()

    local dot, layer, drawn = gameDot(), addon.Crosshair.Layer(), addon.Crosshair.Drawn()
    if not (dot and layer) then return skipCheck(label, "the game's crosshair isn't there") end
    local record = { label = label }
    currentRun.steps[#currentRun.steps + 1] = record

    if not settings.enabled then
        expectEqual(label .. ": our crosshair hidden", false, layer:IsShown())
        expectNear(label .. ": the game's dot back at its own alpha", addon.Crosshair.GameDotAlpha() or 1, dot:GetAlpha())
        record.onScreen = crosshairOnScreen(dot)
        return
    end
    local expected = expectedLook(step, settings)
    expectEqual(label .. ": what's drawn", expected.icon, drawn and drawn.icon)
    if expected.atlas then
        expectEqual(label .. ": its atlas", expected.atlas, type(layer.shape.GetAtlas) == "function" and layer.shape:GetAtlas() or drawn.atlas)
        Debug.CheckNameplateClassColor(label, addon.TargetInfo().classFile)
    elseif expected.icon == "class" and expected.texture then
        expectEqual(label .. ": its sheet", fileAsGameReportsIt(expected.texture), layer.shape:GetTexture())
        -- The game gives the four corners: upper left, lower left, upper right, lower right (x, y each).
        local upperLeftX, upperLeftY, _, lowerLeftY, upperRightX = layer.shape:GetTexCoord()
        expectEqual(label .. ": the class's cell on it", table.concat(expected.texCoord, ","),
            table.concat({ upperLeftX, upperRightX, upperLeftY, lowerLeftY }, ","))
        Debug.CheckNameplateClassColor(label, addon.TargetInfo().classFile)
    elseif expected.icon == "class" then
        recordCheck(label .. ": the class's atlas exists on this client", false, "classicon-<class>", "none")
    else
        expectEqual(label .. ": its file", fileAsGameReportsIt(expected.texture), layer.shape:GetTexture())
    end
    expectEqual(label .. ": our crosshair shown", true, layer:IsShown())
    expectEqual(label .. ": the game's dot see-through", 0, dot:GetAlpha())
    expectNear(label .. ": size", expected.size, layer.shape:GetWidth())
    expectEqual(label .. ": color", expected.tinted and addon.Color("color") or "FFFFFFFF", colorText(layer.shape))
    local borderSize = settings.borderSize
    expectEqual(label .. ": border shown", borderSize > 0, layer.border:IsShown())
    if borderSize > 0 then
        expectNear(label .. ": border size", expected.size + 2 * borderSize, layer.border:GetWidth())
        expectEqual(label .. ": border color", addon.Color("borderColor"), colorText(layer.border))
    end
    record.onScreen = crosshairOnScreen(layer.shape)
    record.visible = layer:IsVisible()
end

-- The class a player target's nameplate shows: its health bar in the class's
-- color (read only; skipped without a nameplate, e.g. friendly nameplates off).
local function classColorText(classFile)
    local classColors = _G.C_ClassColor
    local color = type(classColors) == "table" and type(classColors.GetClassColor) == "function"
        and classColors.GetClassColor(classFile) or (_G.RAID_CLASS_COLORS or {})[classFile]
    return color and addon.FormatColor(color.r, color.g, color.b, 1) or nil
end

function Debug.CheckNameplateClassColor(label, classFile)
    local name = label .. ": its nameplate shows the class's color"
    local namePlates = _G.C_NamePlate
    local nameplate = type(namePlates) == "table" and type(namePlates.GetNamePlateForUnit) == "function"
        and namePlates.GetNamePlateForUnit("target") or nil
    local healthBar = nameplate and nameplate.UnitFrame and nameplate.UnitFrame.healthBar
    if not (healthBar and type(healthBar.GetStatusBarColor) == "function") then
        return skipCheck(name, "no nameplate shown for the target (friendly nameplates off?)")
    end
    local succeeded, red, green, blue = pcall(healthBar.GetStatusBarColor, healthBar)
    local expected = classColorText(classFile)
    if not (succeeded and tonumber(red) and expected) then return skipCheck(name, "its color can't be read") end
    local expectedRed, expectedGreen, expectedBlue = addon.ParseColor(expected)
    local close = math.abs(red - expectedRed) < 0.03 and math.abs(green - expectedGreen) < 0.03 and math.abs(blue - expectedBlue) < 0.03
    recordCheck(name, close, expected, addon.FormatColor(red, green, blue, 1))
end

-- The steps: looks (applied and checked), waits (for the crosshair or a target
-- change), and plain checks.

local STEPS = {}
-- Each step belongs to a part (see Debug.PARTS), the one set when it's added.
local currentPart
local function addLook(label, look, options)
    local step = { label = label, look = look, shows = "crosshair", part = currentPart }
    for key, value in pairs(options or {}) do step[key] = value end
    STEPS[#STEPS + 1] = step
end
-- found: the name its find is kept under (currentRun.found), for steps that require it.
local function addWait(label, waitFor, found)
    STEPS[#STEPS + 1] = { label = label, waitFor = waitFor, found = found, part = currentPart }
end
local function addCheck(label, check) STEPS[#STEPS + 1] = { label = label, check = check, part = currentPart } end

-- 1. No target: the crosshair.
currentPart = "crosshair"
addWait("clear your target", "noTarget")
addLook("the game's dot (addon off)", { enabled = false })
addLook("dot, size 4", {})
addLook("dot, size 12, red", { size = 12, color = "FF3030FF" })
addLook("dot, size 24, black border 2", { size = 24, borderSize = 2 })
addLook("dot, size 24, cyan, white border 4", { size = 24, color = "30D0FFFF", borderSize = 4, borderColor = "FFFFFFFF" })
addLook("dot, size 24, half see-through", { size = 24, color = "FFFFFF80" })
addLook("Jiberish x bold, size 32", { icon = "jiberish:x-bold", size = 32 }, { needsJiberish = true })
addLook("Jiberish circle thin, size 48, red border 2",
    { icon = "jiberish:circle-thin", size = 48, borderSize = 2, borderColor = "FF3030FF" }, { needsJiberish = true })
addLook("no target: the skull chosen, the crosshair stays", { targetIcon = "marker8", size = 12 })
addCheck("every class has its class icon on this client", function(label)
    local missing = {}
    for _, classFile in ipairs(Debug.CLASSES) do
        if not addon.Icons.ClassAtlas(classFile) then missing[#missing + 1] = classFile end
    end
    expectEqual(label, "none missing", #missing == 0 and "none missing" or table.concat(missing, ", "))
end)

-- 2. A friendly player targeted: the icons on it.
currentPart = "friendly"
addWait("select a friendly player", "playerTarget", "class1")
addLook("target, \"None\": the crosshair stays", { targetIcon = "none", size = 12 })
addLook("target: its class icon, size 32", { targetIcon = "class", iconSize = 32 }, { shows = "targetIcon", requires = "class1" })
addLook("target: its class icon, size 48, black border 3", { targetIcon = "class", iconSize = 48, borderSize = 3 },
    { shows = "targetIcon" })
addLook("target: its class icon, Jiberish Fabled Pixels, size 40", { targetIcon = "class", classStyle = "jiberish:fabledpixels",
    iconSize = 40 }, { shows = "targetIcon", needsJiberish = true })
addLook("target: its class icon, Jiberish Fabled Class, size 40", { targetIcon = "class", classStyle = "jiberish:fabledclass",
    iconSize = 40 }, { shows = "targetIcon", needsJiberish = true })
for index = 1, 8 do
    addLook("target: raid marker " .. index .. ", size 32", { targetIcon = "marker" .. index, iconSize = 32 },
        { shows = "targetIcon" })
end
addLook("target: custom texture (question mark), size 32",
    { targetIcon = "custom", customTexture = "Interface\\Icons\\INV_Misc_QuestionMark", iconSize = 32 }, { shows = "targetIcon" })

for number = 2, 1 + Debug.MORE_CLASSES do
    local group = "class" .. number
    addWait("another friendly player, of a class not seen yet (optional)", "newClass", group)
    addLook("friendly player " .. number .. ": its class icon, size 32", { targetIcon = "class", iconSize = 32 },
        { shows = "targetIcon", requires = group })
end

-- 3. A neutral or enemy NPC (move near one first), then the other kind if in range.
currentPart = "monsters"
for _, group in ipairs({ "npc1", "npc2" }) do
    if group == "npc1" then addWait("move near a neutral or enemy NPC", "npcTarget", group)
    else addWait("the other kind of NPC (neutral or enemy), if one is in range (optional)", "otherReaction", group) end
    addLook("NPC: class icon chosen, the crosshair stays", { targetIcon = "class", size = 12 }, { requires = group })
    addLook("NPC: raid marker skull, size 32", { targetIcon = "marker8", iconSize = 32 },
        { shows = "targetIcon", requires = group })
end

-- 4. The target cleared: the crosshair back.
currentPart = "cleared"
addWait("clear the target", "noTarget")
addLook("target cleared: the crosshair back", { targetIcon = "marker8", size = 12, borderSize = 2 })
Debug.STEPS = STEPS

-- What each command runs: /gcc debug all of it, /gcc friendly and /gcc monsters their part.
Debug.PARTS = { debug = { "crosshair", "friendly", "monsters", "cleared" },
    friendly = { "friendly", "cleared" }, monsters = { "monsters", "cleared" } }

-- The steps of a run's parts, in order.
function Debug.StepsFor(runName)
    local wanted, steps = {}, {}
    for _, part in ipairs(Debug.PARTS[runName] or Debug.PARTS.debug) do wanted[part] = true end
    for _, step in ipairs(STEPS) do
        if wanted[step.part] then steps[#steps + 1] = step end
    end
    return steps
end

-- The corner square and the step's name next to it

local MARKER_COLORS = { crosshair = { 1, 1, 0 }, playerTarget = { 0, 0, 1 }, newClass = { 0, 0, 1 },
    noTarget = { 0, 0, 0.5 }, npcTarget = { 0.5, 0, 1 }, otherReaction = { 0.5, 0, 1 } }
local marker
local function showMarker(red, green, blue, text)
    if not marker then
        marker = CreateFrame("Frame", nil, UIParent)
        marker:SetSize(16, 16)
        marker:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        marker:SetFrameStrata("TOOLTIP")
        marker.texture = marker:CreateTexture(nil, "OVERLAY")
        marker.texture:SetAllPoints()
        marker.text = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        marker.text:SetPoint("LEFT", marker, "RIGHT", 6, 0)
        Debug.marker = marker
    end
    marker.texture:SetColorTexture(red, green, blue, 1)
    marker.text:SetText(text or "")
    marker:Show()
end

-- The end: a reload writes the findings to disk. Addon code can't call
-- ReloadUI() on this client, so the box's Reload is a secure /reload button.

local reloadBox
local function showReloadBox(text)
    if InCombatLockdown() then
        Debug.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        Debug.reloadBoxTextAfterCombat = text
        return
    end
    if not reloadBox then
        reloadBox = CreateFrame("Frame", "GamepadCrosshairCustomizerDebugBox", UIParent)
        reloadBox:SetSize(360, 110)
        reloadBox:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
        reloadBox:SetFrameStrata("DIALOG")
        local background = reloadBox:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.85)
        reloadBox.text = reloadBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        reloadBox.text:SetPoint("TOP", reloadBox, "TOP", 0, -14)
        reloadBox.text:SetWidth(330)
        local reloadButton = CreateFrame("Button", "GamepadCrosshairCustomizerDebugReload", reloadBox,
            "SecureActionButtonTemplate,UIPanelButtonTemplate")
        reloadButton:SetAttribute("type", "macro")
        reloadButton:SetAttribute("macrotext", "/reload")
        reloadButton:RegisterForClicks("AnyUp", "AnyDown")
        reloadButton:SetSize(130, 24)
        reloadButton:SetPoint("BOTTOMLEFT", reloadBox, "BOTTOMLEFT", 30, 14)
        reloadButton:SetText(RELOADUI or "Reload")
        local laterButton = CreateFrame("Button", nil, reloadBox, "UIPanelButtonTemplate")
        laterButton:SetSize(130, 24)
        laterButton:SetPoint("BOTTOMRIGHT", reloadBox, "BOTTOMRIGHT", -30, 14)
        laterButton:SetText(LATER or "Later")
        laterButton:SetScript("OnClick", function() reloadBox:Hide() end)
        reloadBox.reloadButton, reloadBox.laterButton = reloadButton, laterButton
    end
    reloadBox.text:SetText(text)
    reloadBox:Show()
    Debug.reloadBox = reloadBox
end

-- Results

local function countResults(run)
    local counts = { pass = 0, fail = 0, skip = 0 }
    for _, check in ipairs(run.checks) do counts[check.result] = counts[check.result] + 1 end
    return counts
end

function Debug.PrintRun(run)
    if not run then say("no saved run yet: /gcc debug"); return end
    local counts = countResults(run)
    local stoppedNote = run.stopped and (" (stopped: " .. run.stopped .. ")") or ""
    say(string.format("%s: %d passed, %d failed, %d skipped%s", run.time or "?", counts.pass, counts.fail, counts.skip, stoppedNote))
    for _, check in ipairs(run.checks) do
        if check.result == "fail" then
            say(string.format("|cffff5555FAIL|r %s: expected %s, got %s", check.name, check.expected or "?", check.actual or "nil"))
        end
    end
end

local function finishRun(stopReason)
    local run = currentRun
    currentRun = nil
    run.stopped = stopReason
    local debugStore = getDebugStore()
    if debugStore.settingsToRestore then
        restoreSettings(debugStore.settingsToRestore)
        debugStore.settingsToRestore = nil
    end
    local counts = countResults(run)
    run.passed, run.failed, run.skipped = counts.pass, counts.fail, counts.skip
    debugStore.runs[#debugStore.runs + 1] = run
    while #debugStore.runs > Debug.RUNS_KEPT do table.remove(debugStore.runs, 1) end
    if stopReason then showMarker(1, 0, 0, "gcc debug stopped: " .. stopReason) elseif marker then marker:Hide() end
    Debug.PrintRun(run)
    say("your settings are back. /reload writes the findings to GamepadCrosshairCustomizerDebugDB")
    showReloadBox(string.format("Gamepad Crosshair Customizer debug: %d passed, %d failed, %d skipped.\n"
        .. "Reload to save the findings (or type /reload).", counts.pass, counts.fail, counts.skip))
end

-- Waits

local function crosshairOnScreenNow()
    local crosshairFrame = _G.GamepadReticle
    return type(crosshairFrame) == "table" and crosshairFrame.Icons ~= nil and crosshairFrame.Icons:IsVisible() == true
end

local function npcOfKind(kindToAvoid)
    local target = addon.TargetInfo()
    return target.exists and not target.isPlayer and (target.reaction == "enemy" or target.reaction == "neutral")
        and target.reaction ~= kindToAvoid
end
local WAIT_CONDITIONS = {
    crosshair = crosshairOnScreenNow,
    playerTarget = function() local target = addon.TargetInfo(); return target.exists and target.isPlayer end,
    newClass = function()
        local target = addon.TargetInfo()
        return target.exists and target.isPlayer and target.classFile ~= nil and not currentRun.classesSeen[target.classFile]
    end,
    noTarget = function() return not addon.TargetInfo().exists end,
    npcTarget = function() return npcOfKind(nil) end,
    otherReaction = function() return npcOfKind(currentRun.found.npc1) end,
}
local WAIT_TEXTS = {
    crosshair = "waiting for the crosshair: touch the controller (the controller UI comes back with its first input)",
    playerTarget = "select a friendly player (F1: yourself)",
    newClass = "select a friendly player of another class, if one is near (optional)",
    noTarget = "clear your target",
    npcTarget = "move near a neutral or enemy NPC (one that won't attack you): it gets selected (Tab by hand)",
    otherReaction = "the other kind of NPC (neutral or enemy), if one is in range (optional)",
}
local WAIT_LIMITS = { newClass = "OPTIONAL_WAIT_SECONDS", otherReaction = "OPTIONAL_WAIT_SECONDS",
    npcTarget = "NPC_WAIT_SECONDS" }
local OPTIONAL_WAITS = { newClass = true, otherReaction = true }

-- What a find is kept as: a player's class, an NPC's reaction.
local function describeFind(waitFor, target)
    if waitFor == "newClass" or waitFor == "playerTarget" then return target.classFile or "unknown class" end
    return target.reaction
end

local runNextStep

-- Polls until the wait is over, or WAIT_SECONDS; records how it went; goes on.
local function wait(waitFor, label, secondsWaited, found)
    if not currentRun then return end
    -- The class search stops at its first miss: nobody else is near.
    if waitFor == "newClass" and currentRun.classSearchOver then return runNextStep() end
    local satisfied = WAIT_CONDITIONS[waitFor]()
    local limit = Debug[WAIT_LIMITS[waitFor] or "WAIT_SECONDS"]
    if satisfied or secondsWaited >= limit then
        if waitFor == "crosshair" then
            currentRun.environment.crosshairWaitSeconds = secondsWaited
            currentRun.environment.crosshairOnScreenAtStart = satisfied
            return runNextStep()
        end
        local target = addon.TargetInfo()
        if OPTIONAL_WAITS[waitFor] then
            if not satisfied then skipCheck(label, "none in range") end   -- optional: skipped, not failed
            if not satisfied and waitFor == "newClass" then currentRun.classSearchOver = true end
        else
            expectEqual(label .. " (within " .. limit .. " s)", true, satisfied)
        end
        if satisfied then
            if found then currentRun.found[found] = describeFind(waitFor, target) end
            if target.isPlayer and target.classFile then currentRun.classesSeen[target.classFile] = true end
        end
        return C_Timer.After(Debug.SECONDS_PER_STEP, runNextStep)
    end
    local color = MARKER_COLORS[waitFor]
    showMarker(color[1], color[2], color[3], "gcc debug: " .. WAIT_TEXTS[waitFor])
    C_Timer.After(Debug.POLL_SECONDS, function() wait(waitFor, label, secondsWaited + Debug.POLL_SECONDS, found) end)
end

runNextStep = function()
    if not currentRun then return end
    currentRun.stepNumber = currentRun.stepNumber + 1
    local step = currentRun.plan[currentRun.stepNumber]
    if not step then return finishRun() end
    local label = currentRun.stepNumber .. "/" .. #currentRun.plan .. ": " .. step.label
    if step.waitFor then return wait(step.waitFor, label, 0, step.found) end
    if step.requires then
        local find = currentRun.found[step.requires]
        if not find then
            -- Nothing of that kind was selected: nothing to check (recorded at its wait).
            showMarker(0, 1, currentRun.stepNumber * Debug.MARKER_BLUE_PER_STEP / 255, label .. " (skipped)")
            return C_Timer.After(0.1, runNextStep)
        end
        label = label .. " (" .. find .. ")"
    end
    if step.needsJiberish and not addon.Icons.JiberishInstalled() then
        label = label .. " (not installed: falls back to the dot)"
    end
    local succeeded, errorMessage = pcall(step.check or checkLook, label, step)
    if not succeeded then recordCheck(label, false, "no error", errorMessage) end
    showMarker(0, 1, currentRun.stepNumber * Debug.MARKER_BLUE_PER_STEP / 255, label)
    C_Timer.After(Debug.SECONDS_PER_STEP, runNextStep)
end

local function describeEnvironment()
    local environment = {}
    if type(GetBuildInfo) == "function" then
        local succeeded, version, build, _, interfaceVersion = pcall(GetBuildInfo)
        if succeeded then environment.version, environment.build, environment.interfaceVersion = version, build, interfaceVersion end
    end
    environment.controllerUI = type(InputUtil) == "table" and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() == true
    environment.crosshairVisible = crosshairOnScreenNow()
    environment.jiberishInstalled = addon.Icons.JiberishInstalled()
    environment.settings = copyCurrentSettings()
    return environment
end

local START_TEXTS = {
    debug = "Stay still; select the targets the corner asks for (or let the screenshot script do it).",
    friendly = "Select a friendly player when the corner asks, then others of other classes, then clear your target.",
    monsters = "Select a neutral or enemy NPC (one that won't attack you) when the corner asks, then the other kind if one is near, then clear your target.",
}

-- runName: "debug" (all of it), "friendly" or "monsters".
function Debug.Start(runName)
    runName = Debug.PARTS[runName] and runName or "debug"
    if currentRun then say("already running"); return end
    if InCombatLockdown() then say("not in combat"); return end
    getDebugStore().settingsToRestore = copyCurrentSettings()
    local plan = Debug.StepsFor(runName)
    currentRun = { name = runName, plan = plan, time = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil,
        environment = describeEnvironment(), checks = {}, steps = {}, stepNumber = 0, found = {}, classesSeen = {} }
    say(string.format("/gcc %s: %d steps. %s", runName, #plan, START_TEXTS[runName]))
    wait("crosshair", "the crosshair on screen", 0)
end

function Debug.Command(arguments)
    if arguments == "" or arguments == "run" then
        Debug.Start("debug")
    elseif arguments == "friendly" or arguments == "monsters" then
        Debug.Start(arguments)
    elseif arguments == "last" then
        local runs = getDebugStore().runs
        Debug.PrintRun(runs[#runs])
    elseif arguments == "clear" then
        getDebugStore().runs = {}
        say("saved runs cleared")
    else
        say("/gcc debug (the whole suite), /gcc friendly, /gcc monsters, /gcc debug last, /gcc debug clear")
    end
end

-- The keys, bound at login (out of combat): a plain button starts a run; two
-- secure macro buttons select and clear the target, as only a key press can.
local function bindKeys()
    if type(SetOverrideBindingClick) ~= "function" then return end
    local startButton = CreateFrame("Button", "GamepadCrosshairCustomizerDebugStart", UIParent)
    startButton:SetScript("OnClick", function() Debug.Start("debug") end)
    SetOverrideBindingClick(startButton, true, Debug.START_KEY, "GamepadCrosshairCustomizerDebugStart", "LeftButton")
    local function macroButton(name, key, macroText)
        local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", macroText)
        button:RegisterForClicks("AnyUp", "AnyDown")
        SetOverrideBindingClick(button, true, key, name, "LeftButton")
    end
    macroButton("GamepadCrosshairCustomizerDebugTarget", Debug.TARGET_KEY, Debug.TARGET_MACRO)
    macroButton("GamepadCrosshairCustomizerDebugClearTarget", Debug.CLEAR_TARGET_KEY, "/cleartarget")
    macroButton("GamepadCrosshairCustomizerDebugTargetEnemy", Debug.TARGET_ENEMY_KEY, "/targetenemy")
end

Debug.eventFrame = CreateFrame("Frame")
Debug.eventFrame:RegisterEvent("PLAYER_LOGIN")
Debug.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
Debug.eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        bindKeys()
        local debugStore = getDebugStore()
        if debugStore.settingsToRestore then
            restoreSettings(debugStore.settingsToRestore)
            debugStore.settingsToRestore = nil
            say("a run was cut short: your settings are back")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if currentRun then finishRun("combat") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local text = Debug.reloadBoxTextAfterCombat
        if text then
            Debug.reloadBoxTextAfterCombat = nil
            showReloadBox(text)
        end
    end
end)
