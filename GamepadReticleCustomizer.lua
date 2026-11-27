-- The settings page (Options > AddOns > Gamepad Reticle Customizer), /gprc and
-- the events. What each setting does is in the other files (SavedSettings.lua
-- lists them).
local ADDON_NAME, addon = ...

local CHAT_PREFIX = "|cff88ccffGamepad Reticle Customizer|r "
addon.PICKER_OPENED_WITHIN = 0.5   -- seconds between a swatch reading its color and the picker showing

local function say(text) print(CHAT_PREFIX .. text) end
local function now() return type(GetTime) == "function" and GetTime() or nil end

-- The color swatches. The settings page's own swatch opens the game's color
-- picker from the game's code (Settings.CreateColorSwatch, SettingsColorSwatchMixin).
-- It speaks "AARRGGBB" with alpha always FF: it sets the color only, and the
-- opacity bar PickerSticks adds sets the alpha. (Opening the picker from addon
-- code instead puts its controller bindings on the game's binding stack tainted:
-- the right stick does nothing and the game refuses its own
-- SetPreferredGamepadInteractTarget, blaming the addon.)
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

-- One color back to its default ("color": white, a shape's own look, Jiberish Fabled Icons'
-- too; "borderColor": black).
function addon.ResetColor(key)
    addon.Settings()[key] = addon.DEFAULTS[key]
    addon.UpdateReticle()
end

-- Jiberish Fabled Icons turned off: offer to turn it on for this character and reload, as
-- the game's AddOns list does it (AddonList.lua:12-24, :578-585, :829, forever
-- branch): EnableAddOn with the player's GUID as the character, then SaveAddOns,
-- then the popup's secure Reload. (With the character's name instead of the GUID,
-- or without SaveAddOns, the reload leaves it off.)
function addon.TellToEnableJiberish()
    addon.Popup.Show({
        text = "Jiberish Fabled Icons is installed but turned off.\nTurn it on and reload to use its reticles and class icons?",
        buttons = {
            { text = "Turn on and reload", reload = true, beforeReload = function()
                C_AddOns.EnableAddOn(addon.Icons.JIBERISH_ADDON, addon.Icons.CharacterKey())
                C_AddOns.SaveAddOns()
            end },
            { text = "Not now" },
        },
    })
end

-- Jiberish Fabled Icons missing: its download link to copy, and a Reload for once it's installed.
function addon.ShowJiberishLink()
    addon.Popup.Show({
        text = "More reticles and class icons come with Jiberish Fabled Icons. To get them:\n"
            .. "• Copy the link (Ctrl+C)\n"
            .. "• Install it\n"
            .. "• Reload",
        copyText = addon.Icons.JIBERISH_LINK,
        buttons = { { text = "Reload", reload = true }, { text = "Close" } },
    })
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
-- that list taints the menu's code: picking fails, and closing the page then makes
-- the game refuse SetPreferredGamepadInteractTarget, blaming this addon. A slider holds a plain number, as the game's own sliders do.
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
    local category, layout = Settings.RegisterVerticalLayoutCategory("Gamepad Reticle Customizer")
    addon.category = category
    local settings = addon.Settings()

    -- onChange (optional): what runs when it changes; the reticle drawn again by default.
    local function addSetting(key, valueType, label, onChange)
        local variableName = "GamepadReticleCustomizer_" .. key
        local setting = Settings.RegisterAddOnSetting(category, variableName, key, settings, valueType, label,
            addon.DEFAULTS[key])
        Settings.SetOnValueChangedCallback(variableName, function() (onChange or addon.UpdateReticle)() end)
        return setting
    end
    local function addSwatch(key, label, tooltip)
        local colorSetting = Settings.RegisterProxySetting(category, "GamepadReticleCustomizer_" .. key .. "Swatch",
            Settings.VarType.String, label, "FF" .. addon.DEFAULTS[key]:sub(1, 6),
            function() return addon.SwatchColor(key) end, function(value) addon.SetSwatchColor(value, key) end)
        Settings.CreateColorSwatch(category, colorSetting, tooltip)
    end
    local canSwatch = type(Settings.RegisterProxySetting) == "function" and type(Settings.CreateColorSwatch) == "function"

    Settings.CreateCheckbox(category, addSetting("enabled", Settings.VarType.Boolean, "Enable"),
        "Draws the controller's aiming dot your way.\n\nTurned off, the game's own dot comes back.")

    -- A choice slider: steps through a list, its label the chosen name; saves the id
    -- under key. afterChange(previousId) (optional) runs once the new id is saved.
    local function addChoice(key, label, list, tooltip, afterChange)
        local entries = list()
        addon.choices[key] = addon.ChoiceIndex(entries, settings[key])
        local variableName = "GamepadReticleCustomizer_" .. key .. "Choice"
        local setting = Settings.RegisterAddOnSetting(category, variableName, key, addon.choices,
            Settings.VarType.Number, label, 1)
        Settings.SetOnValueChangedCallback(variableName, function(_, _, value)
            local entry = entries[math.floor((tonumber(value) or 1) + 0.5)] or entries[1]
            local previousId = settings[key]
            settings[key] = entry.id
            if afterChange then afterChange(previousId) end
            addon.UpdateReticle()
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

    -- The reticle, always shown: its shape, size, color and border.
    local jiberishState = addon.Icons.JiberishState()
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
    -- Without Jiberish Fabled Icons (missing or turned off) the Reticle and Class icons
    -- choices would have one entry each: they're left out, and its button takes the
    -- Class icons row.
    if jiberishInstalled then
        addChoice("icon", "Reticle", addon.Icons.ReticleList,
            "The reticle's shape, always shown.\n\n"
            .. "• Default dot: the game's own\n"
            .. "• The others: Jiberish Fabled Icons' reticles\n\n"
            .. addon.Icons.JIBERISH_CREDIT .. ".",
            keepSizePerKind)
    end

    addon.sizeSetting = addSetting("size", Settings.VarType.Number, "Size")
    Settings.CreateSlider(category, addon.sizeSetting,
        sliderOptions(addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP, function(value)
            local size = math.floor(value + 0.5)
            return size == addon.DEFAULTS.size and (size .. " (default)") or tostring(size)
        end),
        "The reticle's width and height.\n\n"
        .. "• The game's dot is 4\n"
        .. "• The dot and the shapes each keep their own size")

    if canSwatch then
        addon.PickerSticks.Watch(pickerOwner)
        addSwatch("color", "Color",
            "The reticle's color and opacity. White keeps a shape's own look.\n\n"
            .. "On a controller, in the color picker:\n"
            .. "• Left stick: the color\n"
            .. "• Right stick: the brightness\n"
            .. "• D-pad up and down: the opacity\n\n"
            .. "From chat:\n"
            .. "• /gprc RRGGBBAA, e.g. /gprc FF3030FF")
        -- The reset rows show only their button, under their color, lined up with the
        -- other controls: a label of one space reads as empty but isn't "", which
        -- the game would put at the left edge (Blizzard_SettingControls.lua:982-999).
        addButton(" ", "Reset color", function() addon.ResetColor("color") end,
            "Puts the reticle's color back to white.\n\nWhite shows a shape as it was drawn, Jiberish Fabled Icons' too.")
    end
    Settings.CreateSlider(category, addSetting("borderSize", Settings.VarType.Number, "Border"),
        sliderOptions(addon.BORDER_MIN, addon.BORDER_MAX, addon.BORDER_STEP, function(value)
            local borderSize = math.floor(value + 0.5)
            return borderSize == 0 and "Off" or tostring(borderSize)
        end),
        "A border around the reticle or the icon.\n\n"
        .. "• Off: no border\n"
        .. "• 1 to 10: how wide it is\n\n"
        .. "An outline around it, in the border color.")
    if canSwatch then
        addSwatch("borderColor", "Border color", "The border's color and opacity.")
        addButton(" ", "Reset border color", function() addon.ResetColor("borderColor") end,
            "Puts the border's color back to black.")
    end

    -- On a target: the icon instead of the reticle, one choice per kind of target,
    -- the icon size first. The player rows carry the factions' names.
    if type(CreateSettingsListSectionHeaderInitializer) == "function" then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("On a target"))
    end
    Settings.CreateSlider(category, addSetting("iconSize", Settings.VarType.Number, "Icon size"),
        sliderOptions(addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP, function(value) return tostring(math.floor(value + 0.5)) end),
        "The icon's width and height, on a target.")
    for _, kind in ipairs(addon.TARGET_KINDS) do
        addChoice(kind.key, addon.KindLabel(kind), function() return addon.Icons.TargetList(kind.key) end,
            "What shows instead of the reticle on these targets. " .. kind.tooltip .. "\n\n"
            .. "• None: the reticle stays\n"
            .. "• Raid marker: one of the game's 8 markers\n"
            .. "• Icon: one of a set of the game's icons\n\n"
            .. "Shown only while the reticle sits on the target's nameplate, as Gamepad Reticle On Target puts it; "
            .. "the game keeps it in the middle of the screen. Icons keep their own colors.")
        -- Under each player row: its class icons' style, so friend and foe can look
        -- different. Only with Jiberish Fabled Icons: without it, the game's is the one style.
        if kind.classStyleKey and jiberishInstalled then
            addChoice(kind.classStyleKey, addon.ClassStyleLabel(kind), addon.Icons.ClassStyleList,
                "How these players' class icons look, when their row is on Class.\n\n"
                .. "• Default: the game's own\n"
                .. "• The others: Jiberish Fabled Icons' class icon styles\n\n"
                .. addon.Icons.JIBERISH_CREDIT .. ".")
        end
    end
    if jiberishState == "missing" then
        addButton("More looks", "Get Jiberish Fabled Icons", function() addon.ShowJiberishLink() end,
            "More looks come with the Jiberish Fabled Icons addon:\n\n"
            .. "• 11 class icon styles\n"
            .. "• 16 reticle shapes\n\n"
            .. "Once it's installed and you've reloaded, they're offered here.")
    elseif jiberishState ~= "enabled" then
        addButton("More looks", "Enable Jiberish Fabled Icons", function() addon.TellToEnableJiberish() end,
            "Jiberish Fabled Icons is installed but turned off.\n\n"
            .. "Turn it on to get its class icon styles and reticle shapes here.")
    end

    -- Nearby: the game's icons on what's around you, not only your target.
    if type(CreateSettingsListSectionHeaderInitializer) == "function" then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Nearby"))
    end
    Settings.CreateCheckbox(category,
        addSetting("objectIcons", Settings.VarType.Boolean, "Object icons", addon.ObjectIcons.Apply),
        "The game's interact icons on more of what's around you:\n\n"
        .. "• Ore, herbs, skinning, chests, mailboxes, chairs\n"
        .. "• From farther away: 60 yards instead of 30\n"
        .. "• In a wider arc\n"
        .. "• The interact key on a keyboard too\n\n"
        .. "Turned off, your own game settings come back.")
    Settings.CreateCheckbox(category,
        addSetting("questIcons", Settings.VarType.Boolean, "Quest icons", addon.QuestIcons.Refresh),
        "Beside the nameplates of what a quest still needs:\n\n"
        .. "• A sword: kill it\n"
        .. "• A bag: it drops an item you need\n\n"
        .. "The game can hide quest text from addons in dungeons, raids and fights; "
        .. "nameplates shown then get theirs once it's back.")

    addon.RelatedAddons.AddButtons(addButton)

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
-- The target's nameplate coming or going (on or off screen) switches between icon and reticle.
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
-- The game's interaction icon for an NPC can settle a moment after it's selected,
-- and changes with what you can interact with: drawn again then too.
eventFrame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
-- A friendly NPC whose icon is its job: drawn once, this short beat after it's
-- selected, when the game's icon for it is ready (no wrong icon first).
addon.JOB_ICON_DELAY_SECONDS = 0.1
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        addon.Settings()
        pcall(addon.RegisterSettings)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SOFT_INTERACT_CHANGED" then
        addon.UpdateReticle()
    elseif event == "PLAYER_TARGET_CHANGED" then
        local settings = addon.Settings()
        local kindKey = addon.TargetKindKey(addon.TargetInfo())
        if kindKey and settings[kindKey] == "job" then
            -- Until then, other redraws (the reticle moving onto the nameplate) wait.
            addon.jobIconPending = true
            C_Timer.After(addon.JOB_ICON_DELAY_SECONDS, function()
                addon.jobIconPending = nil
                addon.UpdateReticle()
            end)
        else
            addon.jobIconPending = nil
            addon.UpdateReticle()
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        -- Only the target's own nameplate matters (name is the unit, "nameplate3").
        local succeeded, isTarget = pcall(UnitIsUnit, name, "target")
        -- An answer the game hides from addons (a secret value) can't be compared: drawn again then too.
        local hidden = type(issecretvalue) == "function" and issecretvalue(isTarget)
        if not succeeded or hidden or isTarget ~= false then addon.UpdateReticle() end
    end
end)

-- /gprc                opens the settings (/gamepadreticlecustomizer works too)
-- /gprc RRGGBBAA       sets the color
-- /gprc debug ...      development builds only (Debug.lua);
--                     /gprc friendly and /gprc monsters run its parts
SLASH_GAMEPADRETICLECUSTOMIZER1 = "/gprc"
SLASH_GAMEPADRETICLECUSTOMIZER2 = "/gamepadreticlecustomizer"
SlashCmdList.GAMEPADRETICLECUSTOMIZER = function(message)
    local text = tostring(message or ""):match("^%s*(.-)%s*$")
    local command, arguments = text:match("^(%S+)%s*(.-)$")
    command = command and command:lower()
    if text == "" then return addon.Open() end
    if command == "debug" or command == "friendly" or command == "monsters" then
        if not addon.Debug then return addon.Open() end   -- the release has no debug suite
        return addon.Debug.Command(command == "debug" and arguments:lower() or command)
    end
    if addon.SetColor(text) then
        say("reticle color: " .. addon.Color())
    else
        say("usage: /gprc RRGGBBAA (hex, alpha last), e.g. /gprc FF3030FF")
    end
end
