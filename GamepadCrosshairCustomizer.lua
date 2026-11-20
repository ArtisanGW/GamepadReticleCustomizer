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

-- One color back to its default ("color": white, a shape's own look, JiberishUI's
-- too; "borderColor": black).
function addon.ResetColor(key)
    addon.Settings()[key] = addon.DEFAULTS[key]
    addon.UpdateCrosshair()
end

function addon.TellToEnableJiberish()
    addon.TextBox.Tell("JiberishUI Fabled Icons is installed but turned off. To use its shapes and class icons: "
        .. "open the game menu > AddOns, tick JiberishUI Fabled Icons, then reload (or restart the game).")
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

    -- A choice slider: steps through a list, its label the chosen name; saves the id
    -- under key. afterChange(previousId) (optional) runs once the new id is saved.
    local function addChoice(key, label, list, tooltip, afterChange)
        local entries = list()
        addon.choices[key] = addon.ChoiceIndex(entries, settings[key])
        local variableName = "GamepadCrosshairCustomizer_" .. key .. "Choice"
        local setting = Settings.RegisterAddOnSetting(category, variableName, key, addon.choices,
            Settings.VarType.Number, label, 1)
        Settings.SetOnValueChangedCallback(variableName, function(_, _, value)
            local entry = entries[math.floor((tonumber(value) or 1) + 0.5)] or entries[1]
            local previousId = settings[key]
            settings[key] = entry.id
            if afterChange then afterChange(previousId) end
            addon.UpdateCrosshair()
        end)
        Settings.CreateSlider(category, setting, sliderOptions(1, #entries, 1, function(value)
            local entry = entries[math.floor(value + 0.5)] or entries[1]
            return entry.label
        end), tooltip)
        return setting
    end

    local function addButton(name, buttonText, onClick, tooltip)
        if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
        layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
    end

    -- The crosshair, always shown: its shape, size, color and border.
    local jiberishState = addon.Icons.JiberishState()
    addon.jiberishAtSettings = addon.Icons.JiberishRawState()   -- for /gcc debug's records
    local jiberishInstalled = jiberishState == "enabled"
    -- The dot and the shapes each keep their own size: switching between them saves
    -- the size of the one left and brings back the other's (a shape starts at 24:
    -- at the dot's 4 it can't be seen).
    local function keepSizePerKind(previousIcon)
        local wasDot, isDot = previousIcon == "dot", settings.icon == "dot"
        if wasDot == isDot then return end
        if wasDot then settings.dotSize = settings.size else settings.shapeSize = settings.size end
        local size = isDot and settings.dotSize or settings.shapeSize
        if addon.sizeSetting then addon.sizeSetting:SetValue(size) else settings.size = size end
    end
    addChoice("icon", "Crosshair", addon.Icons.CrosshairList,
        "The crosshair's shape, always shown: the game's own dot (Default dot)"
        .. (jiberishInstalled and (", or one of JiberishUI's crosshairs. " .. addon.Icons.JIBERISH_CREDIT
            .. " (" .. addon.Icons.JIBERISH_LINK .. ").") or ". More shapes come with JiberishUI Fabled Icons (Get JiberishUI Icons... below)."),
        keepSizePerKind)

    addon.sizeSetting = addSetting("size", Settings.VarType.Number, "Size")
    Settings.CreateSlider(category, addon.sizeSetting,
        sliderOptions(addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP, function(value)
            local size = math.floor(value + 0.5)
            return size == addon.DEFAULTS.size and (size .. " (default)") or tostring(size)
        end),
        "The crosshair's width and height. The game's dot is 4. The dot and the shapes each keep their own size.")

    if canSwatch then
        addon.PickerSticks.Watch(pickerOwner)
        addSwatch("color", "Color",
            "The crosshair's color and opacity, e.g. to see it better on the ground. White keeps a shape's own look. "
            .. "On a controller: left stick for the color, right stick for the brightness, D-pad up and down for the opacity. "
            .. "Also from chat: /gcc RRGGBBAA (hex, alpha last), e.g. /gcc FF3030FF.")
        -- The reset rows show only their button, under their color, lined up with the
        -- other controls: a label of one space reads as empty but isn't "", which
        -- the game would put at the left edge (Blizzard_SettingControls.lua:982-999).
        addButton(" ", "Reset color", function() addon.ResetColor("color") end,
            "Puts the crosshair's color back to white: a shape's own look, JiberishUI's too.")
    end
    Settings.CreateSlider(category, addSetting("borderSize", Settings.VarType.Number, "Border"),
        sliderOptions(addon.BORDER_MIN, addon.BORDER_MAX, addon.BORDER_STEP, function(value)
            local borderSize = math.floor(value + 0.5)
            return borderSize == 0 and "Off" or tostring(borderSize)
        end),
        "A border around the crosshair or the icon, this wide: the same picture, larger, behind it, in the border color.")
    if canSwatch then
        addSwatch("borderColor", "Border color", "The border's color and opacity.")
        addButton(" ", "Reset border color", function() addon.ResetColor("borderColor") end,
            "Puts the border's color back to black.")
    end

    -- On a target: the icon instead of the crosshair.
    addon.targetIconSlider = addChoice("targetIcon", "On a target", addon.Icons.TargetList,
        "What shows instead of the crosshair while your target's nameplate is on screen (vendors, guards "
        .. "and minions keep the crosshair unless their nameplates are on in Options > Nameplates): None (the "
        .. "crosshair stays), Player Class (a player's class icon; any other target keeps the crosshair), one of the game's raid markers, "
        .. "or one of a set of the game's icons; the preview shows it big. Icons keep their own colors.")
    addChoice("classStyle", "Class icons", addon.Icons.ClassStyleList,
        "How a player's class icon looks: the game's own (Default)"
        .. (jiberishInstalled and ", or one of JiberishUI's class icon styles (Fabled, Fabled Pixels, Fabled Class...)." or
            ". More styles come with JiberishUI Fabled Icons (Get JiberishUI Icons... below)."))
    Settings.CreateSlider(category, addSetting("iconSize", Settings.VarType.Number, "Icon size"),
        sliderOptions(addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP, function(value) return tostring(math.floor(value + 0.5)) end),
        "The icon's width and height on a target.")

    if jiberishState == "missing" then
        addButton("More shapes", "Get JiberishUI Icons...", function() addon.ShowJiberishLink() end,
            "16 more crosshair shapes and 11 class icon styles come with the JiberishUI Fabled Icons addon. "
            .. "Once it's installed (and after /reload), they're in the Crosshair and Class icons choices.")
    elseif jiberishState == "disabled" then
        addButton("More shapes", "Enable JiberishUI Icons...", function() addon.TellToEnableJiberish() end,
            "JiberishUI Fabled Icons is installed but turned off, so its shapes and class icons aren't offered. "
            .. "Turn it on in the AddOns list, then reload.")
    end

    addon.RelatedAddon.AddButton(addButton)

    Settings.RegisterAddOnCategory(category)
    addon.Preview.Watch()
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
-- The target's nameplate coming or going (on or off screen) switches between icon and crosshair.
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        addon.Settings()
        pcall(addon.RegisterSettings)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED" then
        addon.UpdateCrosshair()
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        -- Only the target's own nameplate matters (name is the unit, "nameplate3").
        local succeeded, isTarget = pcall(UnitIsUnit, name, "target")
        if not succeeded or isTarget ~= false then addon.UpdateCrosshair() end
    end
end)

-- /gcc                opens the settings
-- /gcc RRGGBBAA       sets the color
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
    if addon.SetColor(text) then
        say("crosshair color: " .. addon.Color())
    else
        say("usage: /gcc RRGGBBAA (hex, alpha last), e.g. /gcc FF3030FF")
    end
end
