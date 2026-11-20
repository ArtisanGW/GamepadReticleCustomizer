-- A small box with one line of text: to type something (a texture path) and
-- confirm it, or to copy something (a web link: the game can't open one, so the
-- text is shown selected, ready for Ctrl+C). Our own frame, built once; Escape
-- or Close shuts it.
--   addon.TextBox.Ask(title, text, onAccept)  type, then OK calls onAccept(text)
--   addon.TextBox.Copy(title, text)           copy
local _, addon = ...

local TextBox = {}
addon.TextBox = TextBox

local box

local function build()
    box = CreateFrame("Frame", "GamepadCrosshairCustomizerTextBox", UIParent)
    box:SetSize(460, 120)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    box:SetFrameStrata("DIALOG")
    box:EnableMouse(true)
    local background = box:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.85)

    box.title = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.title:SetPoint("TOP", box, "TOP", 0, -14)
    box.title:SetWidth(430)

    box.editBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    box.editBox:SetSize(410, 24)
    box.editBox:SetPoint("TOP", box.title, "BOTTOM", 0, -12)
    box.editBox:SetAutoFocus(false)
    box.editBox:SetScript("OnEscapePressed", function() box:Hide() end)
    box.editBox:SetScript("OnEnterPressed", function() if box.okButton:IsShown() then box.okButton:Click() end end)

    box.okButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.okButton:SetSize(130, 24)
    box.okButton:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 40, 14)
    box.okButton:SetText(OKAY or "OK")
    box.okButton:SetScript("OnClick", function()
        local onAccept = box.onAccept
        box:Hide()
        if onAccept then onAccept(box.editBox:GetText()) end
    end)

    box.closeButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.closeButton:SetSize(130, 24)
    box.closeButton:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -40, 14)
    box.closeButton:SetText(CLOSE or "Close")
    box.closeButton:SetScript("OnClick", function() box:Hide() end)
end

local function open(title, text, onAccept)
    if not box then build() end
    box.title:SetText(title)
    box.editBox:SetText(text or "")
    box.onAccept = onAccept
    box.okButton:SetShown(onAccept ~= nil)
    box:Show()
    box.editBox:SetFocus()
    box.editBox:HighlightText()
    TextBox.box = box   -- for the tests
end

function TextBox.Ask(title, text, onAccept) open(title, text, onAccept) end
function TextBox.Copy(title, text) open(title, text, nil) end
