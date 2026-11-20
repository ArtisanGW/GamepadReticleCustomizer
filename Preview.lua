-- A live preview of the reticle beside the settings page: the game's reticle
-- is behind the settings window while you change it. Two cells: the reticle, and
-- the icon shown on a target (for a player's class, your own class as the
-- example). Each cell shows its picture zoomed to fill it, so a small icon (a
-- Jiberish Fabled Icons class icon at 24) can be seen properly, with a copy at its real size
-- in the corner. The window keeps one size whatever is chosen. Painted as the
-- reticle is (Reticle.Paint), redrawn on every change.
--
-- It looks like a game window: built as the settings window's own frame is
-- (SettingsFrameTemplate, Mainline/Blizzard_SettingsPanelTemplates.xml:4, forever
-- branch: FlatPanelBackgroundTemplate, a NineSlicePanelTemplate border in the
-- ButtonFrameTemplateNoPortrait layout, a GameFontNormal title) but without its
-- close button, and each cell an InsetFrameTemplate, as inside the game's windows.
-- No template here has a button.
--
-- Its own frame on the settings window, not part of the game's settings list:
-- nothing of the game's runs our code for it, and it has no buttons, so the
-- controller's navigation doesn't stop on it. It shows while our page is the one
-- open (SettingsPanel:GetCurrentCategory, Blizzard_SettingsPanel.lua:971, forever
-- branch), checked a few times a second while the window is open.
local _, addon = ...

local Preview = { CHECK_SECONDS = 0.25, CELL_SIZE = 120, ZOOMED_FILL = 0.8, REAL_SIZE_CORNER = 40,
    TITLE_HEIGHT = 24, PADDING = 14, LABEL_HEIGHT = 30 }
addon.Preview = Preview

local frame, watcher

local function newCell(label, column)
    local cell = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    cell:SetSize(Preview.CELL_SIZE, Preview.CELL_SIZE)
    cell:SetPoint("TOPLEFT", frame, "TOPLEFT", Preview.PADDING + column * (Preview.CELL_SIZE + Preview.PADDING),
        -(Preview.TITLE_HEIGHT + Preview.PADDING))
    local background = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
    background:SetPoint("TOPLEFT", cell, "TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
    background:SetColorTexture(0.22, 0.24, 0.2, 1)   -- a dull ground color, as behind the real reticle
    -- The zoomed view, in the middle.
    cell.border = cell:CreateTexture(nil, "BORDER")
    cell.border:SetPoint("CENTER", cell, "CENTER")
    cell.shape = cell:CreateTexture(nil, "ARTWORK")
    cell.shape:SetPoint("CENTER", cell, "CENTER")
    -- The real size, in the bottom-right corner, on its own darker square.
    local corner = CreateFrame("Frame", nil, cell)
    corner:SetSize(Preview.REAL_SIZE_CORNER, Preview.REAL_SIZE_CORNER)
    corner:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
    local cornerBackground = corner:CreateTexture(nil, "BACKGROUND")
    cornerBackground:SetAllPoints()
    cornerBackground:SetColorTexture(0.12, 0.13, 0.11, 1)
    cell.realBorder = corner:CreateTexture(nil, "BORDER")
    cell.realBorder:SetPoint("CENTER", corner, "CENTER")
    cell.realShape = corner:CreateTexture(nil, "ARTWORK")
    cell.realShape:SetPoint("CENTER", corner, "CENTER")
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -6)
    cell.label:SetWidth(Preview.CELL_SIZE + 10)
    cell.label:SetText(label)
    return cell
end

local function build(settingsPanel)
    frame = CreateFrame("Frame", "GamepadReticleCustomizerPreview", settingsPanel)
    frame:SetSize(Preview.PADDING + 2 * (Preview.CELL_SIZE + Preview.PADDING),
        Preview.TITLE_HEIGHT + Preview.PADDING + Preview.CELL_SIZE + Preview.LABEL_HEIGHT)
    frame:SetPoint("TOPLEFT", settingsPanel, "TOPRIGHT", 4, 0)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata(settingsPanel:GetFrameStrata())
    -- The settings window's own background and border (SettingsFrameTemplate's pieces).
    frame.Bg = CreateFrame("Frame", nil, frame, "FlatPanelBackgroundTemplate")
    frame.Bg:SetFrameLevel(frame:GetFrameLevel())
    frame.Bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -18)
    frame.Bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    frame.NineSlice = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    frame.NineSlice:SetAllPoints()
    if type(NineSliceUtil) == "table" and type(NineSliceUtil.ApplyLayoutByName) == "function" then
        NineSliceUtil.ApplyLayoutByName(frame.NineSlice, "ButtonFrameTemplateNoPortrait")
    end
    frame.title = frame.NineSlice:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
    frame.title:SetText("Preview")
    frame.reticle = newCell("Reticle", 0)
    frame.onTarget = newCell("On a target", 1)
    frame:Hide()
    Preview.frame = frame
end

-- The example target for the "On a target" cell: a player of your own class.
local function exampleTarget()
    local classFile
    if type(UnitClass) == "function" then classFile = select(2, UnitClass("player")) end
    return { exists = true, hasNameplate = true, reticleOnNameplate = true, isPlayer = true, classFile = classFile }
end

-- A look's full width, border included, at its real size.
local function fullWidth(look)
    return look.size + 2 * addon.Clamp(addon.Settings().borderSize, addon.BORDER_MIN, addon.BORDER_MAX, 0)
end

-- A cell: the look zoomed to fill ZOOMED_FILL of the cell in the middle, and at its
-- real size in the corner (shrunk only when it's bigger than the corner).
local function paintCell(cell, look)
    local width = fullWidth(look)
    addon.Reticle.Paint(cell.shape, cell.border, look, Preview.CELL_SIZE * Preview.ZOOMED_FILL / width)
    local cornerRoom = Preview.REAL_SIZE_CORNER * Preview.ZOOMED_FILL
    addon.Reticle.Paint(cell.realShape, cell.realBorder, look, math.min(1, cornerRoom / width))
end

function Preview.Refresh()
    if not (frame and frame:IsShown()) then return end
    local settings = addon.Settings()
    paintCell(frame.reticle, addon.Reticle.Choose(settings, { exists = false }))
    paintCell(frame.onTarget, addon.Reticle.Choose(settings, exampleTarget()))
    frame.onTarget.label:SetText(settings.targetIcon == "none" and "On a target: the reticle stays" or "On a target")
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
