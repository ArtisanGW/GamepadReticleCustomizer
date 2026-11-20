-- The settings page (Options > AddOns > Gamepad Crosshair Customizer), /gcc and
-- the events. What each setting does is in the other files (SavedSettings.lua
-- lists them).
local ADDON_NAME, addon = ...

local CHAT_PREFIX = "|cff88ccffGamepad Crosshair Customizer|r "
addon.PICKER_OPENED_WITHIN = 0.5   -- seconds between a swatch reading its color and the picker showing

local function say(text) print(CHAT_PREFIX .. text) end
local function now() return type(GetTime) == "function" and GetTime() or nil end

-- The color swatches. The settings page's own swatch opens the game's color
-- picker from the game's code (Settings.CreateColorSwatch, SettingsColorSwatchMixin).
-- It speaks "AARRGGBB" with alpha always FF: it sets the color only, and the
-- opacity bar PickerSticks adds sets the alpha. (Opening the picker from addon
-- code instead put its controller bindings on the game's binding stack tainted:
-- the right stick did nothing and the game refused its own
-- SetPreferredGamepadInteractTarget, blaming the addon. Seen in game, 2026-11-19.)
local pickerAskedAt    -- when a swatch last read its color: it's about to open the picker
local pickerColorKey   -- which color that swatch is for: "color" or "borderColor"

function addon.SwatchColor(key)
    pickerAskedAt, pickerColorKey = now(), key or "color"
    return "FF" .. addon.Color(key):sub(1, 6)
end

function addon.SetSwatchColor(value, key)
    local text = tostring(value or ""):gsub("^#", "")
    if #text ~= 8 or not text:match("^%x+$") then return end
    addon.SetColor(text:sub(3, 8) .. addon.Color(key):sub(7, 8), key)
end

-- PickerSticks' owner: which picker is ours, and the opacity of the color it's for.
local pickerOwner = {
    OpenedThePicker = function()
        local time = now()
        return pickerAskedAt ~= nil and time ~= nil and time - pickerAskedAt <= addon.PICKER_OPENED_WITHIN
    end,
    Opacity = function() return addon.Opacity(pickerColorKey) end,
    SetOpacity = function(alpha) addon.SetOpacity(alpha, pickerColorKey) end,
}

-- The custom texture: typed in a box (the settings page has no text field).
function addon.AskCustomTexture()
    addon.TextBox.Ask("A texture path for the crosshair, e.g. Interface\\Icons\\INV_Misc_QuestionMark",
        addon.Settings().customTexture, function(text) addon.SetCustomTexture(text) end)
end

function addon.SetCustomTexture(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text == "" then return false end
    addon.Settings().customTexture = text
    addon.Settings().targetIcon = "custom"
    if addon.targetIconSlider then addon.targetIconSlider:SetValue(addon.ChoiceIndex(addon.Icons.TargetList(), "custom")) end
    addon.UpdateCrosshair()
    return true
end

function addon.ShowJiberishLink()
    addon.TextBox.Copy("More shapes: install JiberishUI Fabled Icons (copy the link with Ctrl+C), then /reload.",
        addon.Icons.JIBERISH_LINK)
end

-- Settings page

local function sliderOptions(minimum, maximum, step, formatLabel)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    local rightLabel = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
        and MinimalSliderWithSteppersMixin.Label.Right
    if rightLabel and options.SetLabelFormatter then options:SetLabelFormatter(rightLabel, formatLabel) end
    return options
end

-- The shape choices are sliders, not dropdowns: a settings dropdown's menu is
-- built from the addon's own list, and steered by the controller (SmartNavigation)
-- that list taints the menu's code: picking failed, and closing the page then made
-- the game refuse SetPreferredGamepadInteractTarget, blaming this addon (seen in
-- game, 2026-11-20). A slider holds a plain number, as the game's own sliders do.
-- Its position (in addon.choices, not saved) picks the id saved under its key.
addon.choices = {}

function addon.ChoiceIndex(list, id)
    for index, entry in ipairs(list) do
        if entry.id == id then return index end
    end
    return 1
end

function addon.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("Gamepad Crosshair Customizer")
    addon.category = category
    local settings = addon.Settings()

    local function addSetting(key, valueType, label)
        local variableName = "GamepadCrosshairCustomizer_" .. key
        local setting = Settings.RegisterAddOnSetting(category, variableName, key, settings, valueType, label,
            addon.DEFAULTS[key])
        Settings.SetOnValueChangedCallback(variableName, function() addon.UpdateCrosshair() end)
        return setting
    end
    local function addSwatch(key, label, tooltip)
        local colorSetting = Settings.RegisterProxySetting(category, "GamepadCrosshairCustomizer_" .. key .. "Swatch",
            Settings.VarType.String, label, "FF" .. addon.DEFAULTS[key]:sub(1, 6),
            function() return addon.SwatchColor(key) end, function(value) addon.SetSwatchColor(value, key) end)
        Settings.CreateColorSwatch(category, colorSetting, tooltip)
    end
    local canSwatch = type(Settings.RegisterProxySetting) == "function" and type(Settings.CreateColorSwatch) == "function"

    Settings.CreateCheckbox(category, addSetting("enabled", Settings.VarType.Boolean, "Enable"),
        "Draws the controller's aiming dot (the controller UI's crosshair) your way. Turned off, the game's own dot comes back.")

    -- A choice slider: steps through a list, its label the chosen name; saves the id under key.
    local function addChoice(key, label, list, tooltip)
        local entries = list()
        addon.choices[key] = addon.ChoiceIndex(entries, settings[key])
        local variableName = "GamepadCrosshairCustomizer_" .. key .. "Choice"
        local setting = Settings.RegisterAddOnSetting(category, variableName, key, addon.choices,
            Settings.VarType.Number, label, 1)
        Settings.SetOnValueChangedCallback(variableName, function(_, _, value)
            local entry = entries[math.floor((tonumber(value) or 1) + 0.5)] or entries[1]
            settings[key] = entry.id
            addon.UpdateCrosshair()
        end)
        Settings.CreateSlider(category, setting, sliderOptions(1, #entries, 1, function(value)
            local entry = entries[math.floor(value + 0.5)] or entries[1]
            return entry.label
        end), tooltip)
        return setting
    end

    local jiberishInstalled = addon.Icons.JiberishInstalled()
    addChoice("icon", "Crosshair", addon.Icons.CrosshairList,
        "The crosshair's shape, always shown: the game's dot"
        .. (jiberishInstalled and (", or one of JiberishUI's crosshairs. " .. addon.Icons.JIBERISH_CREDIT
            .. " (" .. addon.Icons.JIBERISH_LINK .. ").") or ". More shapes come with JiberishUI Fabled Icons (Get JiberishUI Icons... below)."))

    Settings.CreateSlider(category, addSetting("size", Settings.VarType.Number, "Size"),
        sliderOptions(addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP, function(value)
            local size = math.floor(value + 0.5)
            return size == addon.DEFAULTS.size and (size .. " (the game's)") or tostring(size)
        end),
        "The crosshair's width and height. The game's dot is 4.")

    if canSwatch then
        addon.PickerSticks.Watch(pickerOwner)
        addSwatch("color", "Color",
            "The crosshair's color and opacity, e.g. to see it better on the ground. "
            .. "On a controller: left stick for the color, right stick for the brightness, D-pad up and down for the opacity. "
            .. "Also from chat: /gcc RRGGBBAA (hex, alpha last), e.g. /gcc FF3030FF.")
    end

    addon.targetIconSlider = addChoice("targetIcon", "On a target", addon.Icons.TargetList,
        "What shows instead of the crosshair while you have a target: nothing (the crosshair stays), "
        .. "a player's class icon (any other target keeps the crosshair), one of the game's raid markers, "
        .. "or a texture of your own (Custom texture...). Icons keep their own colors.")
    Settings.CreateSlider(category, addSetting("iconSize", Settings.VarType.Number, "Icon size"),
        sliderOptions(addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP, function(value) return tostring(math.floor(value + 0.5)) end),
        "The icon's width and height on a target.")

    Settings.CreateSlider(category, addSetting("borderSize", Settings.VarType.Number, "Border"),
        sliderOptions(addon.BORDER_MIN, addon.BORDER_MAX, addon.BORDER_STEP, function(value)
            local borderSize = math.floor(value + 0.5)
            return borderSize == 0 and "Off" or tostring(borderSize)
        end),
        "A border around the crosshair or the icon, this wide: the same picture, larger, behind it, in the border color.")
    if canSwatch then
        addSwatch("borderColor", "Border color", "The border's color and opacity.")
    end

    if layout and type(CreateSettingsButtonInitializer) == "function" then
        layout:AddInitializer(CreateSettingsButtonInitializer("Custom texture", "Custom texture...",
            function() addon.AskCustomTexture() end,
            "Type the path of any texture in the game to show it on a target. Also from chat: /gcc texture <path>.",
            true))
        if not jiberishInstalled then
            layout:AddInitializer(CreateSettingsButtonInitializer("More shapes", "Get JiberishUI Icons...",
                function() addon.ShowJiberishLink() end,
                "16 more crosshair shapes come with the JiberishUI Fabled Icons addon. "
                .. "Once it's installed, they're in the Crosshair list.", true))
        end
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
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        addon.Settings()
        pcall(addon.RegisterSettings)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED" then
        addon.UpdateCrosshair()
    end
end)

-- /gcc                opens the settings
-- /gcc RRGGBBAA       sets the color
-- /gcc texture <path> uses that texture as the crosshair
-- /gcc debug ...      the in-game test suite (Debug.lua, not in the release);
--                     /gcc friendly and /gcc monsters run its parts
SLASH_GAMEPADCROSSHAIRCUSTOMIZER1 = "/gcc"
SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER = function(message)
    local text = tostring(message or ""):match("^%s*(.-)%s*$")
    local command, arguments = text:match("^(%S+)%s*(.-)$")
    command = command and command:lower()
    if text == "" then return addon.Open() end
    if command == "debug" or command == "friendly" or command == "monsters" then
        if not addon.Debug then return addon.Open() end   -- the release has no debug suite
        return addon.Debug.Command(command == "debug" and arguments:lower() or command)
    end
    if command == "texture" then
        if addon.SetCustomTexture(arguments) then say("crosshair texture: " .. arguments)
        else say("usage: /gcc texture <path>, e.g. /gcc texture Interface\\Icons\\INV_Misc_QuestionMark") end
        return
    end
    if addon.SetColor(text) then
        say("crosshair color: " .. addon.Color())
    else
        say("usage: /gcc RRGGBBAA (hex, alpha last), e.g. /gcc FF3030FF; /gcc texture <path>")
    end
end
