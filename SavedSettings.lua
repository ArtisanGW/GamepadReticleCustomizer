-- GamepadReticleCustomizer customizes the controller's aiming dot (the controller
-- UI's reticle, Blizzard's GamepadReticle). This file: the saved settings.
--
-- The other files, one job each:
--   Color.lua         colors as "RRGGBBAA" text, the dot's and the border's
--   Icons.lua         the reticle's shapes (the game's dot, Jiberish Fabled Icons' reticle
--                     shapes when installed) and the icons on a target (its class,
--                     the game's raid markers, a hand-picked set of the game's icons)
--   Target.lua        what's targeted now: whether there's a target, a player's class
--   Reticle.lua     draws the reticle, or the icon on a target, on the game's reticle
--   PickerSticks.lua  the game's color picker on a controller
--   Popup.lua         a popup in the game's own style, with a secure Reload when needed
--   GamepadReticleCustomizer.lua  the settings page, /grc and the events
--   Debug.lua         /grc debug, the in-game test suite (not in the release)
local _, addon = ...
_G.GamepadReticleCustomizer = addon

--   enabled:       draw the customized reticle (off: the game's own dot back).
--   icon:          the reticle's shape, always shown (Icons.lua): "dot", the game's
--                  own, or a Jiberish Fabled Icons reticle shape.
--   color:         the reticle's color, 32 bits as "RRGGBBAA" (hex, alpha last).
--   size:          its width and height, in the reticle's own units (the game's dot is 4).
--   dotSize, shapeSize: the size each kind had when last left (the dot's, a shape's),
--                  brought back when switching to it.
--   targetIcon:    what shows instead while you have a target: "none" (the reticle
--                  stays), "class" (a player's class; others keep the reticle), a raid
--                  marker or one of the game's icons. Icons keep their own colors.
--   classStyle:    the class icon's style (Icons.lua): "game" or a Jiberish Fabled Icons class sheet.
--   iconSize:      the icon's width and height.
--   borderSize:    how far the border reaches out around either (0: no border).
--   borderColor:   the border's color, "RRGGBBAA".
addon.DEFAULTS = { enabled = true, icon = "dot", color = "FFFFFFFF", size = 4, dotSize = 4, shapeSize = 32, targetIcon = "none", classStyle = "game", iconSize = 32,
    borderSize = 0, borderColor = "000000FF" }
addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP = 2, 64, 1
addon.BORDER_MIN, addon.BORDER_MAX, addon.BORDER_STEP = 0, 10, 1


function addon.Settings()
    if type(GamepadReticleCustomizerDB) ~= "table" then GamepadReticleCustomizerDB = {} end
    local settings = GamepadReticleCustomizerDB
    -- Before targets had their own icon, one Shape held markers and custom
    -- textures too: those are icons on a target now.
    if settings.targetIcon == nil and settings.icon ~= nil and not addon.Icons.IsReticleShape(settings.icon) then
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
