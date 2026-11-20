-- GamepadCrosshairCustomizer customizes the controller's aiming dot (the controller
-- UI's crosshair, Blizzard's GamepadReticle). This file: the saved settings.
--
-- The other files, one job each:
--   Color.lua         colors as "RRGGBBAA" text, the dot's and the border's
--   Icons.lua         the crosshair's shapes (the game's dot, JiberishUI's crosshair
--                     shapes when installed) and the icons on a target (its class,
--                     the game's raid markers, a hand-picked set of the game's icons)
--   Target.lua        what's targeted now: whether there's a target, a player's class
--   Crosshair.lua     draws the crosshair, or the icon on a target, on the game's crosshair
--   PickerSticks.lua  the game's color picker on a controller
--   TextBox.lua       a small box to type or copy a line of text
--   GamepadCrosshairCustomizer.lua  the settings page, /gcc and the events
--   Debug.lua         /gcc debug, the in-game test suite (not in the release)
local _, addon = ...
_G.GamepadCrosshairCustomizer = addon

--   enabled:       draw the customized crosshair (off: the game's own dot back).
--   icon:          the crosshair's shape, always shown (Icons.lua): "dot", the game's
--                  own, or a JiberishUI crosshair shape.
--   color:         the crosshair's color, 32 bits as "RRGGBBAA" (hex, alpha last).
--   size:          its width and height, in the crosshair's own units (the game's dot is 4).
--   dotSize, shapeSize: the size each kind had when last left (the dot's, a shape's),
--                  brought back when switching to it.
--   targetIcon:    what shows instead while you have a target: "none" (the crosshair
--                  stays), "class" (a player's class; others keep the crosshair), a raid
--                  marker or one of the game's icons. Icons keep their own colors.
--   classStyle:    the class icon's style (Icons.lua): "game" or a JiberishUI class sheet.
--   iconSize:      the icon's width and height.
--   borderSize:    how far the border reaches out around either (0: no border).
--   borderColor:   the border's color, "RRGGBBAA".
addon.DEFAULTS = { enabled = true, icon = "dot", color = "FFFFFFFF", size = 4, dotSize = 4, shapeSize = 24, targetIcon = "none", classStyle = "game", iconSize = 24,
    borderSize = 0, borderColor = "000000FF" }
addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP = 2, 64, 1
addon.BORDER_MIN, addon.BORDER_MAX, addon.BORDER_STEP = 0, 10, 1


function addon.Settings()
    if type(GamepadCrosshairCustomizerDB) ~= "table" then GamepadCrosshairCustomizerDB = {} end
    local settings = GamepadCrosshairCustomizerDB
    -- Before targets had their own icon, one Shape held markers and custom
    -- textures too: those are icons on a target now.
    if settings.targetIcon == nil and settings.icon ~= nil and not addon.Icons.IsCrosshairShape(settings.icon) then
        settings.targetIcon, settings.icon = settings.icon, "dot"
    end
    -- A custom texture path (and the icon picker's file ids) are gone: that icon becomes none.
    if settings.targetIcon == "custom" then settings.targetIcon = "none" end
    settings.customTexture = nil
    for key, defaultValue in pairs(addon.DEFAULTS) do
        if settings[key] == nil then settings[key] = defaultValue end
    end
    return settings
end

-- A number setting within its range, or its default if it isn't a number.
function addon.Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end
