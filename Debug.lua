-- /gcc debug: an in-game test suite. It puts each look on the real crosshair, one
-- step every Debug.SECONDS_PER_STEP, checks what the game shows (our textures'
-- size, color and file, the game's dot hidden or back), puts your own settings
-- back, and keeps the findings in GamepadCrosshairCustomizerDebugDB (written to
-- disk on /reload). Not in the release zip (.pkgmeta).
--   /gcc debug         runs the suite (out of combat, controller UI on, no target)
--   /gcc debug last    prints the last run's findings again
--   /gcc debug clear   empties the saved runs
-- A fight stops the run; a reload during one puts your settings back at login.
--
-- Screenshots: tests/screenshot_debug.sh (outside the game) shoots each step. The
-- square in the top-left corner says which step is on screen: green, with the
-- step number in its blue (step x Debug.MARKER_BLUE_PER_STEP / 255); red once the
-- run stopped; gone when it's done. Each step's crosshair position on screen (in
-- screen pixels, from the top-left) is saved with the run, for the crops.
local addon = _G.GamepadCrosshairCustomizer
local Debug = { SECONDS_PER_STEP = 2.5, RUNS_KEPT = 10, MARKER_BLUE_PER_STEP = 8,
    -- Starts a run like /gcc debug, for tests/screenshot_debug.sh (keys from outside
    -- reach the game; typing in its chat isn't tried). Free among the dev tools' keys.
    START_KEY = "ALT-CTRL-SHIFT-C",
    -- The game hides its crosshair while the cursor shows, and after a reload the
    -- controller UI only comes back with the controller's first input: the run
    -- waits for the crosshair, up to this long, so the shots show it. (It doesn't
    -- switch the controller UI on itself: InputDeviceInterfaceStyle switches the
    -- whole interface, and from addon code that would run the game's switch tainted.)
    CROSSHAIR_WAIT_SECONDS = 60, CROSSHAIR_POLL_SECONDS = 0.5 }
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

local function colorText(region)
    return addon.FormatColor(region:GetVertexColor())
end

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

-- Applies a look, then checks the game shows it.
local function checkLook(label, look)
    local settings = addon.Settings()
    for key, value in pairs(addon.DEFAULTS) do settings[key] = value end
    for key, value in pairs(look) do
        if addon.DEFAULTS[key] ~= nil then settings[key] = value end
    end
    addon.UpdateCrosshair()

    local dot, layer, drawn = gameDot(), addon.Crosshair.Layer(), addon.Crosshair.Drawn()
    if not (dot and layer) then return skipCheck(label, "the game's crosshair isn't there") end
    local step = { label = label }
    currentRun.steps[#currentRun.steps + 1] = step

    if not settings.enabled then
        expectEqual(label .. ": our crosshair hidden", false, layer:IsShown())
        expectNear(label .. ": the game's dot back at its own alpha", addon.Crosshair.GameDotAlpha() or 1, dot:GetAlpha())
        step.onScreen = crosshairOnScreen(dot)
        return
    end
    local expectedIcon = look.icon or "dot"
    local expectedTexture = addon.Icons.Texture(expectedIcon, settings.customTexture)
    if look.expectFallback then expectedIcon, expectedTexture = "dot", addon.Icons.GAME_DOT_TEXTURE end
    expectEqual(label .. ": icon drawn", expectedIcon, drawn and drawn.icon)
    expectEqual(label .. ": its file", fileAsGameReportsIt(expectedTexture), layer.shape:GetTexture())
    expectEqual(label .. ": our crosshair shown", true, layer:IsShown())
    expectEqual(label .. ": the game's dot see-through", 0, dot:GetAlpha())
    expectNear(label .. ": size", settings.size, layer.shape:GetWidth())
    expectEqual(label .. ": color", addon.Color("color"), colorText(layer.shape))
    local borderSize = settings.borderSize
    expectEqual(label .. ": border shown", borderSize > 0, layer.border:IsShown())
    if borderSize > 0 then
        expectNear(label .. ": border size", settings.size + 2 * borderSize, layer.border:GetWidth())
        expectEqual(label .. ": border color", addon.Color("borderColor"), colorText(layer.border))
    end
    step.onScreen = crosshairOnScreen(layer.shape)
    step.visible = layer:IsVisible()
end

-- The steps

local STEPS = {}
local function addLook(label, look) STEPS[#STEPS + 1] = { label = label, look = look } end

addLook("the game's dot (addon off)", { enabled = false })
addLook("dot, size 4", {})
addLook("dot, size 12, red", { size = 12, color = "FF3030FF" })
addLook("dot, size 24, black border 2", { size = 24, borderSize = 2 })
addLook("dot, size 24, cyan, white border 4", { size = 24, color = "30D0FFFF", borderSize = 4, borderColor = "FFFFFFFF" })
addLook("dot, size 24, half see-through", { size = 24, color = "FFFFFF80" })
for index = 1, 8 do
    addLook("raid marker " .. index .. ", size 32", { icon = "marker" .. index, size = 32 })
end
addLook("skull, size 32, black border 3", { icon = "marker8", size = 32, borderSize = 3 })
addLook("Jiberish x bold, size 32", { icon = "jiberish:x-bold", size = 32, needsJiberish = true })
addLook("Jiberish circle thin, size 48, red border 2",
    { icon = "jiberish:circle-thin", size = 48, borderSize = 2, borderColor = "FF3030FF", needsJiberish = true })
addLook("custom texture (question mark), size 32",
    { icon = "custom", customTexture = "Interface\\Icons\\INV_Misc_QuestionMark", size = 32 })
Debug.STEPS = STEPS

-- The corner square and the step's name next to it

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

local function runNextStep()
    if not currentRun then return end
    currentRun.stepNumber = currentRun.stepNumber + 1
    local step = STEPS[currentRun.stepNumber]
    if not step then return finishRun() end
    local label = currentRun.stepNumber .. "/" .. #STEPS .. ": " .. step.label
    if step.look.needsJiberish and not addon.Icons.JiberishInstalled() then
        -- Without the addon its shapes aren't offered: the game's dot shape is drawn instead.
        label = label .. " (not installed: falls back to the dot)"
        step.look.expectFallback = true
    end
    local look = {}
    for key, value in pairs(step.look) do
        if addon.DEFAULTS[key] ~= nil then look[key] = value end
    end
    look.expectFallback = step.look.expectFallback
    local succeeded, errorMessage = pcall(checkLook, label, look)
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
    environment.crosshairVisible = type(_G.GamepadReticle) == "table" and GamepadReticle:IsVisible() == true
    environment.jiberishInstalled = addon.Icons.JiberishInstalled()
    environment.target = type(UnitExists) == "function" and UnitExists("target") == true
    environment.settings = copyCurrentSettings()
    return environment
end

function Debug.Start()
    if currentRun then say("already running"); return end
    if InCombatLockdown() then say("not in combat"); return end
    getDebugStore().settingsToRestore = copyCurrentSettings()
    currentRun = { time = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil,
        environment = describeEnvironment(), checks = {}, steps = {}, stepNumber = 0 }
    if not currentRun.environment.crosshairVisible then
        say("the crosshair isn't on screen (controller UI off, or the cursor shows): checks run, screenshots won't show it")
    end
    say(string.format("running %d steps, about %d s. Stay still.", #STEPS, math.ceil(#STEPS * Debug.SECONDS_PER_STEP)))
    Debug.WaitForCrosshair(0)
end

local function crosshairOnScreenNow()
    local crosshairFrame = _G.GamepadReticle
    return type(crosshairFrame) == "table" and crosshairFrame.Icons ~= nil and crosshairFrame.Icons:IsVisible() == true
end

-- Before the first step: waits until the game shows its crosshair (the square
-- yellow meanwhile, which the screenshot script reads as "not started").
function Debug.WaitForCrosshair(secondsWaited)
    if not currentRun then return end
    if crosshairOnScreenNow() or secondsWaited >= Debug.CROSSHAIR_WAIT_SECONDS then
        currentRun.environment.crosshairWaitSeconds = secondsWaited
        currentRun.environment.crosshairOnScreenAtStart = crosshairOnScreenNow()
        return runNextStep()
    end
    showMarker(1, 1, 0, "gcc debug: waiting for the crosshair: touch the controller (the controller UI comes back with its first input)")
    C_Timer.After(Debug.CROSSHAIR_POLL_SECONDS, function() Debug.WaitForCrosshair(secondsWaited + Debug.CROSSHAIR_POLL_SECONDS) end)
end

function Debug.Command(arguments)
    if arguments == "" or arguments == "run" then
        Debug.Start()
    elseif arguments == "last" then
        local runs = getDebugStore().runs
        Debug.PrintRun(runs[#runs])
    elseif arguments == "clear" then
        getDebugStore().runs = {}
        say("saved runs cleared")
    else
        say("/gcc debug (run the suite), /gcc debug last, /gcc debug clear")
    end
end

Debug.eventFrame = CreateFrame("Frame")
Debug.eventFrame:RegisterEvent("PLAYER_LOGIN")
Debug.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
Debug.eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if type(SetOverrideBindingClick) == "function" then
            local startButton = CreateFrame("Button", "GamepadCrosshairCustomizerDebugStart", UIParent)
            startButton:SetScript("OnClick", function() Debug.Start() end)
            SetOverrideBindingClick(startButton, true, Debug.START_KEY, "GamepadCrosshairCustomizerDebugStart", "LeftButton")
        end
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
