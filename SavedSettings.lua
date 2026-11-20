-- GamepadCrosshairCustomizer customizes the controller's aiming dot (the controller
-- UI's crosshair, Blizzard's GamepadReticle). This file: the saved settings.
--
-- The other files, one job each:
--   Color.lua         colors as "RRGGBBAA" text, the dot's and the border's
--   Icons.lua         the shapes the dot can take (the game's dot, its raid markers,
--                     JiberishUI's shapes when installed, a texture path of your own)
--   Crosshair.lua     draws the shape, its size and border on the game's crosshair
--   PickerSticks.lua  the game's color picker on a controller
--   TextBox.lua       a small box to type or copy a line of text
--   GamepadCrosshairCustomizer.lua  the settings page, /gcc and the events
--   Debug.lua         /gcc debug, the in-game test suite (not in the release)
local _, addon = ...
_G.GamepadCrosshairCustomizer = addon

--   enabled:       draw the customized crosshair (off: the game's own dot back).
--   color:         its color, 32 bits as "RRGGBBAA" (hex, alpha last).
--   size:          its width and height, in the crosshair's own units (the game's dot is 4).
--   borderSize:    how far the border reaches out around it (0: no border).
--   borderColor:   the border's color, "RRGGBBAA".
--   icon:          which shape (see Icons.lua): "dot" is the game's own.
--   customTexture: the texture path the "custom" icon uses.
addon.DEFAULTS = { enabled = true, color = "FFFFFFFF", size = 4, borderSize = 0, borderColor = "000000FF",
    icon = "dot", customTexture = "" }
addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP = 2, 64, 1
addon.BORDER_MIN, addon.BORDER_MAX, addon.BORDER_STEP = 0, 10, 1

function addon.Settings()
    if type(GamepadCrosshairCustomizerDB) ~= "table" then GamepadCrosshairCustomizerDB = {} end
    local settings = GamepadCrosshairCustomizerDB
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
