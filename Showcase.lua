-- Development builds only (never in the release, .pkgmeta): a screenshot tour of
-- our controller addons, driven from outside the game by tests/screenshot_showcase.sh
-- with one key, SHOWCASE_KEY. Each press does the next step:
--   settings   opens a settings page (a slash command); the script scrolls it with the
--              mouse wheel so every slider shows its handle (the game draws them late).
--              Nothing here touches the game's settings window: that taints it.
--   target     selects targets with the game's own /targetfriend, /targetfriendplayer
--              or /targetenemy until the kind wanted comes up (addon code can't target)
--   look       changes this addon's look on the same target
-- The square in the top-left corner says what's going on: magenta while busy
-- (the script waits, or presses again to look for the next target), red when a
-- target wasn't found (no shot), gone when the screen is ready for a shot.
-- Your settings are saved at the first step and put back after the last (and at
-- the next login, should a reload cut the tour short).
local addon = _G.GamepadReticleCustomizer
local Showcase = { KEY = "ALT-CTRL-SHIFT-B", CHECK_DELAY_SECONDS = 0.4, TRIES = 15 }
addon.Showcase = Showcase

-- The look shown: an icon for each kind of target.
Showcase.LOOK = { friendlyPlayerIcon = "class", otherFactionIcon = "faction", friendlyNpcIcon = "job",
    neutralNpcIcon = "dots", enemyNpcIcon = "swords", iconSize = 32 }

local function interaction(target)
    if not (target.exists and not target.isPlayer and target.reaction == "friendly") then return nil end
    local kind, name = addon.Icons.InteractionIcon("target")
    return kind == "icon" and tostring(name) or nil
end

-- The steps, in order: { name (the shot's file name), kind, macro, wanted, look }.
Showcase.STEPS = {
    { name = "settings-reticle-customizer", kind = "settings", macro = "/grc" },
    { name = "settings-reticle-on-target", kind = "settings", macro = "/grt" },
    { name = "settings-camera-offset", kind = "settings", macro = "/gco" },
    { name = "npc-job-icon", kind = "target", macro = "/targetfriend",
        wanted = function(target) local name = interaction(target); return name and not name:find("Quest", 1, true) end },
    { name = "npc-quest-giver", kind = "target", macro = "/targetfriend",
        wanted = function(target) local name = interaction(target); return name and name:find("Quest", 1, true) end },
    { name = "player-class-icon", kind = "target", macro = "/targetfriendplayer",
        wanted = function(target) return target.isPlayer and not target.otherFaction end },
    { name = "player-faction-badge", kind = "look", look = { friendlyPlayerIcon = "faction" } },
    { name = "neutral-npc-dots", kind = "target", macro = "/targetenemy",
        wanted = function(target) return not target.isPlayer and target.reaction == "neutral" end },
}

local button, marker, stepIndex, tries

local function store()
    if type(GamepadReticleCustomizerDebugDB) ~= "table" then GamepadReticleCustomizerDebugDB = {} end
    return GamepadReticleCustomizerDebugDB
end

local function setMarker(red, green, blue)
    if not marker then
        marker = CreateFrame("Frame", nil, UIParent)
        marker:SetSize(16, 16)
        marker:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        marker:SetFrameStrata("TOOLTIP")
        marker.texture = marker:CreateTexture(nil, "OVERLAY")
        marker.texture:SetAllPoints()
    end
    if not red then return marker:Hide() end
    marker.texture:SetColorTexture(red, green, blue, 1)
    marker:Show()
end

local function applyLook(look)
    local settings = addon.Settings()
    for key, value in pairs(look) do settings[key] = value end
    addon.UpdateReticle()
end

local function restore()
    local saved = store().showcaseRestore
    if not saved then return end
    local settings = addon.Settings()
    for key, value in pairs(saved) do settings[key] = value end
    store().showcaseRestore = nil
    addon.UpdateReticle()
end

local function setMacro(step)
    if InCombatLockdown() then return end
    -- A look step runs no macro (the target stays); after the last step, the target is cleared.
    local macro = "/cleartarget"
    if step then macro = step.macro or "" end
    button:SetAttribute("macrotext", macro)
end

local function advance()
    stepIndex, tries = stepIndex + 1, 0
    setMacro(Showcase.STEPS[stepIndex])
end

-- After each press: is this step's screen ready?
local function check()
    local step = Showcase.STEPS[stepIndex]
    if not step then
        restore()
        setMarker(nil)
        stepIndex = nil
        return
    end
    if step.kind == "settings" then
        setMarker(nil)   -- the script scrolls the page (the mouse wheel) before shooting
        return advance()
    end
    if step.kind == "look" then
        applyLook(step.look)
        setMarker(nil)
        return advance()
    end
    tries = tries + 1
    if step.wanted(addon.TargetInfo()) then
        setMarker(nil)
        return advance()
    end
    if tries >= Showcase.TRIES then
        setMarker(1, 0, 0)   -- not found: no shot, the script moves on
        return advance()
    end
    setMarker(1, 0, 1)   -- still looking: press again
end

local function onClick()
    if InCombatLockdown() then return end
    if not stepIndex then
        stepIndex, tries = 1, 0
        local copy, settings = {}, addon.Settings()
        for key in pairs(addon.DEFAULTS) do copy[key] = settings[key] end
        store().showcaseRestore = copy
        applyLook(Showcase.LOOK)
    end
    setMarker(1, 0, 1)
    C_Timer.After(Showcase.CHECK_DELAY_SECONDS, check)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    restore()   -- a tour cut short by a reload: your settings back
    if type(SetOverrideBindingClick) ~= "function" then return end
    if type(UIParent.HookScript) ~= "function" then return end   -- not the game (the tests' fake one)
    button = CreateFrame("Button", "GamepadReticleCustomizerShowcase", UIParent, "SecureActionButtonTemplate")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", Showcase.STEPS[1].macro)
    button:RegisterForClicks("AnyDown")
    button:HookScript("OnClick", onClick)   -- after the macro ran
    SetOverrideBindingClick(button, true, Showcase.KEY, "GamepadReticleCustomizerShowcase", "LeftButton")
end)
