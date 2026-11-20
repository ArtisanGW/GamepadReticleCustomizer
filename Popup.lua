-- A popup that looks like the game's own: its dialog border (DialogBorderTemplate,
-- forever branch Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml:69, the frame
-- of the game's popups), its fonts and buttons. A message, an optional line to copy
-- (a web link: the game can't open one, so it's shown selected for Ctrl+C), and up
-- to three buttons; one can be Reload, a secure /reload button (addon code can't
-- call ReloadUI() on this client), with something to do just before it reloads.
--   addon.Popup.Show({ text = "...", copyText = "https://...",
--       buttons = { { text = "Reload", reload = true, beforeReload = function() end },
--                   { text = "Close" } } })
-- A button without onClick closes the popup. It's our own frame, not the game's
-- StaticPopup (shared windows the controller steers: our code in them broke its
-- navigation before). Holding a secure button, it can't be shown in a fight: it
-- opens once the fight is over.
local _, addon = ...

local Popup = { WIDTH = 440, BUTTON_WIDTH = 170, BUTTON_HEIGHT = 24, BUTTONS = 3 }
addon.Popup = Popup

local frame, waitingForCombatEnd, pendingOptions

local function build()
    frame = CreateFrame("Frame", "GamepadCrosshairCustomizerPopup", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetWidth(Popup.WIDTH)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -135)   -- where the game's popups open
    frame.Border = CreateFrame("Frame", nil, frame, "DialogBorderTemplate")
    frame.Border:SetAllPoints()

    frame.text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.text:SetPoint("TOP", frame, "TOP", 0, -20)
    frame.text:SetWidth(Popup.WIDTH - 50)

    frame.editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.editBox:SetSize(Popup.WIDTH - 70, 24)
    frame.editBox:SetPoint("TOP", frame.text, "BOTTOM", 0, -12)
    frame.editBox:SetAutoFocus(false)
    frame.editBox:SetScript("OnEscapePressed", function() frame:Hide() end)

    -- Plain buttons, and one secure Reload (created now, out of combat).
    frame.buttons = {}
    for index = 1, Popup.BUTTONS do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(Popup.BUTTON_WIDTH, Popup.BUTTON_HEIGHT)
        button:SetScript("OnClick", function(self)
            local onClick = self.onClick
            frame:Hide()
            if onClick then onClick() end
        end)
        frame.buttons[index] = button
    end
    frame.reloadButton = CreateFrame("Button", "GamepadCrosshairCustomizerPopupReload", frame,
        "SecureActionButtonTemplate,UIPanelButtonTemplate")
    frame.reloadButton:SetSize(Popup.BUTTON_WIDTH, Popup.BUTTON_HEIGHT)
    frame.reloadButton:SetAttribute("type", "macro")
    frame.reloadButton:SetAttribute("macrotext", "/reload")
    frame.reloadButton:RegisterForClicks("AnyUp", "AnyDown")
    frame.reloadButton:SetScript("PreClick", function(self)
        if self.beforeReload then pcall(self.beforeReload) end
    end)
    Popup.frame = frame
end

local function layout(options)
    frame.text:SetText(options.text or "")
    -- Centered as the game's popups are; a list ("•" lines) reads better left-aligned.
    frame.text:SetJustifyH((options.text or ""):find("•", 1, true) and "LEFT" or "CENTER")
    local height = 20 + (frame.text:GetStringHeight() or 40) + 16
    frame.editBox:SetShown(options.copyText ~= nil)
    frame.editBox:SetText(options.copyText or "")
    if options.copyText then height = height + 36 end

    for _, button in ipairs(frame.buttons) do button:Hide() end
    frame.reloadButton:Hide()
    local shown = {}
    local plainIndex = 0
    for _, spec in ipairs(options.buttons or { { text = CLOSE or "Close" } }) do
        local button
        if spec.reload then
            button = frame.reloadButton
            button.beforeReload = spec.beforeReload
        else
            plainIndex = plainIndex + 1
            button = frame.buttons[plainIndex]
            button.onClick = spec.onClick
        end
        button:SetText(spec.text)
        shown[#shown + 1] = button
    end
    -- The buttons in a centered row at the bottom, as the game's popups have them.
    local gap = 10
    local rowWidth = #shown * Popup.BUTTON_WIDTH + (#shown - 1) * gap
    for index, button in ipairs(shown) do
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", frame, "BOTTOM", -rowWidth / 2 + (index - 1) * (Popup.BUTTON_WIDTH + gap), 16)
        button:Show()
    end
    frame:SetHeight(height + Popup.BUTTON_HEIGHT + 16)
end

function Popup.Show(options)
    if InCombatLockdown() then
        -- A frame holding a secure button can't be shown in combat: after the fight.
        pendingOptions = options
        if not waitingForCombatEnd then
            waitingForCombatEnd = CreateFrame("Frame")
            waitingForCombatEnd:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if pendingOptions then local waiting = pendingOptions; pendingOptions = nil; Popup.Show(waiting) end
            end)
        end
        waitingForCombatEnd:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    if not frame then build() end
    layout(options)
    frame:Show()
    if options.copyText then
        frame.editBox:SetFocus()
        frame.editBox:HighlightText()
    end
    return true
end

function Popup.Hide() if frame then frame:Hide() end end
