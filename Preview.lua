-- A live preview of the crosshair beside the settings page: the game's crosshair
-- is behind the settings window while you change it. Two cells: the crosshair as
-- it's drawn, and the icon shown on a target (for a player's class, your own
-- class as the example). Painted as the crosshair is (Crosshair.Paint), redrawn on
-- every change.
--
-- Its own frame on the settings window, not part of the game's settings list:
-- nothing of the game's runs our code for it, and it has no buttons, so the
-- controller's navigation doesn't stop on it. It shows while our page is the one
-- open (SettingsPanel:GetCurrentCategory, Blizzard_SettingsPanel.lua:971, forever
-- branch), checked a few times a second while the window is open.
local _, addon = ...

local Preview = { CHECK_SECONDS = 0.25, CELL_SIZE = 84 }
addon.Preview = Preview

local frame, watcher

local function newCell(label, column)
    local cell = CreateFrame("Frame", nil, frame)
    cell:SetSize(Preview.CELL_SIZE, Preview.CELL_SIZE)
    cell:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + column * (Preview.CELL_SIZE + 12), -34)
    local background = cell:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.22, 0.24, 0.2, 1)   -- a dull ground color, as behind the real crosshair
    cell.border = cell:CreateTexture(nil, "BORDER")
    cell.border:SetPoint("CENTER", cell, "CENTER")
    cell.shape = cell:CreateTexture(nil, "ARTWORK")
    cell.shape:SetPoint("CENTER", cell, "CENTER")
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -4)
    cell.label:SetWidth(Preview.CELL_SIZE + 10)
    cell.label:SetText(label)
    return cell
end

local function build(settingsPanel)
    frame = CreateFrame("Frame", "GamepadCrosshairCustomizerPreview", settingsPanel)
    frame:SetSize(12 + 2 * (Preview.CELL_SIZE + 12), 160)
    frame:SetPoint("TOPLEFT", settingsPanel, "TOPRIGHT", 6, 0)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata(settingsPanel:GetFrameStrata())
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.85)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -10)
    frame.title:SetText("Preview")
    frame.crosshair = newCell("Crosshair", 0)
    frame.onTarget = newCell("On a target", 1)
    frame:Hide()
    Preview.frame = frame
end

-- The example target for the "On a target" cell: a player of your own class.
local function exampleTarget()
    local classFile
    if type(UnitClass) == "function" then classFile = select(2, UnitClass("player")) end
    return { exists = true, hasNameplate = true, isPlayer = true, classFile = classFile }
end

function Preview.Refresh()
    if not (frame and frame:IsShown()) then return end
    local settings = addon.Settings()
    local noTarget = { exists = false }
    addon.Crosshair.Paint(frame.crosshair.shape, frame.crosshair.border, addon.Crosshair.Choose(settings, noTarget))
    local onTarget = addon.Crosshair.Choose(settings, exampleTarget())
    addon.Crosshair.Paint(frame.onTarget.shape, frame.onTarget.border, onTarget)
    frame.onTarget.label:SetText(settings.targetIcon == "none" and "On a target: the crosshair stays" or "On a target")
    -- The addon off: the game's own dot; shown dimmed so the page still previews your choices.
    frame:SetAlpha(settings.enabled and 1 or 0.5)
end

-- Shows the preview while our page is open (checked a few times a second while
-- the settings window is).
function Preview.Watch()
    local settingsPanel = _G.SettingsPanel
    if watcher or type(settingsPanel) ~= "table" or type(settingsPanel.GetCurrentCategory) ~= "function" then return end
    build(settingsPanel)
    watcher = CreateFrame("Frame", nil, settingsPanel)
    local sinceCheck = Preview.CHECK_SECONDS
    watcher:SetScript("OnUpdate", function(_, elapsed)
        sinceCheck = sinceCheck + elapsed
        if sinceCheck < Preview.CHECK_SECONDS then return end
        sinceCheck = 0
        local succeeded, category = pcall(settingsPanel.GetCurrentCategory, settingsPanel)
        local ours = succeeded and category ~= nil and category == addon.category
        if ours and not frame:IsShown() then
            frame:Show()
            Preview.Refresh()
        elseif not ours and frame:IsShown() then
            frame:Hide()
        end
    end)
    Preview.watcher = watcher
end
