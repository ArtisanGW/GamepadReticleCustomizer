-- GamepadCrosshairCustomizer: customizes the controller's aiming dot (the controller
-- UI's crosshair). This file: the settings page (Options > AddOns > Gamepad
-- Crosshair Customizer), /gcc and the events. The color is in Color.lua, the
-- color picker's controller sticks in PickerSticks.lua.
local ADDON_NAME, addon = ...

local CHAT_PREFIX = "|cff88ccffGamepad Crosshair Customizer|r "
addon.PICKER_OPENED_WITHIN = 0.5   -- seconds between the swatch reading the color and the picker showing

-- The settings page's own color swatch opens the game's color picker from the
-- game's code (Settings.CreateColorSwatch, SettingsColorSwatchMixin). It speaks
-- "AARRGGBB" with alpha always FF: it sets the color only, and the opacity bar
-- PickerSticks adds sets the alpha. (Opening the picker from addon code instead put
-- its controller bindings on the game's binding stack tainted: the right stick
-- did nothing and the game refused its own SetPreferredGamepadInteractTarget,
-- blaming the addon. Seen in game, 2026-11-19.)
local pickerAskedAt   -- when the swatch last read the color: it's about to open the picker

local function now() return type(GetTime) == "function" and GetTime() or nil end

function addon.SwatchColor()
    pickerAskedAt = now()
    return "FF" .. addon.Color():sub(1, 6)
end

function addon.SetSwatchColor(value)
    local text = tostring(value or ""):gsub("^#", "")
    if #text ~= 8 or not text:match("^%x+$") then return end
    addon.SetColor(text:sub(3, 8) .. addon.Color():sub(7, 8))
end

-- For PickerSticks: whether the picker that just showed was opened by our swatch.
function addon.OpenedThePicker()
    local time = now()
    return pickerAskedAt ~= nil and time ~= nil and time - pickerAskedAt <= addon.PICKER_OPENED_WITHIN
end

function addon.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local category = Settings.RegisterVerticalLayoutCategory("Gamepad Crosshair Customizer")
    addon.category = category

    local enabledSetting = Settings.RegisterAddOnSetting(category, "GamepadCrosshairCustomizer_enabled", "enabled",
        addon.Settings(), Settings.VarType.Boolean, "Enable", addon.DEFAULTS.enabled)
    Settings.SetOnValueChangedCallback("GamepadCrosshairCustomizer_enabled", function() addon.ColorCrosshair() end)
    Settings.CreateCheckbox(category, enabledSetting,
        "Colors the controller's aiming dot (the controller UI's crosshair). Turned off, its own white comes back.")

    if type(Settings.RegisterProxySetting) == "function" and type(Settings.CreateColorSwatch) == "function" then
        addon.PickerSticks.Watch(addon)
        local colorSetting = Settings.RegisterProxySetting(category, "GamepadCrosshairCustomizer_color",
            Settings.VarType.String, "Crosshair color", "FFFFFFFF", addon.SwatchColor, addon.SetSwatchColor)
        Settings.CreateColorSwatch(category, colorSetting,
            "The controller's aiming dot's color and opacity, e.g. to see it better on the ground. "
            .. "On a controller: left stick for the color, right stick for the brightness, D-pad up and down for the opacity. "
            .. "Also from chat: /gcc RRGGBBAA (hex, alpha last), e.g. /gcc FF3030FF.")
    end

    Settings.RegisterAddOnCategory(category)
end

function addon.Open()
    if addon.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(addon.category:GetID())
    end
end

-- Events

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        addon.Settings()
        pcall(addon.RegisterSettings)
    elseif event == "PLAYER_ENTERING_WORLD" then
        addon.ColorCrosshair()
    end
end)

-- /gcc opens the settings; /gcc RRGGBBAA sets the color.
SLASH_GAMEPADCROSSHAIRCUSTOMIZER1 = "/gcc"
SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER = function(message)
    local text = tostring(message or ""):match("^%s*(.-)%s*$")
    if text == "" then return addon.Open() end
    if addon.SetColor(text) then
        print(CHAT_PREFIX .. "crosshair color: " .. addon.Color())
    else
        print(CHAT_PREFIX .. "usage: /gcc RRGGBBAA (hex, alpha last), e.g. /gcc FF3030FF")
    end
end
