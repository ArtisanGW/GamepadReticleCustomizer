-- GamepadCrosshairColor: the color and opacity of the controller's aiming dot.
--
-- The dot is the controller UI's GamepadReticle (Blizzard_Gamepad, loaded with the
-- game, not on demand): its Icons.StandardIcon, a small white circle that Blizzard
-- never tints itself (forever branch, Blizzard_Gamepad/UI/Reticle/GamepadReticle.xml:94).
-- So it's tinted once at login and again only when the color changes. The dot's
-- own color is kept first and put back when the addon is switched off.
--
-- This file: the saved color and the tint. PickerSticks.lua: the color picker on a
-- controller. GamepadCrosshairColor.lua: the settings page, /gcc and the events.
local _, addon = ...
_G.GamepadCrosshairColor = addon

--   enabled: tint the dot (off: the dot's own color back).
--   color:   the dot's color, 32 bits as "RRGGBBAA" (hex, alpha last).
addon.DEFAULTS = { enabled = true, color = "FFFFFFFF" }

function addon.Settings()
    if type(GamepadCrosshairColorDB) ~= "table" then GamepadCrosshairColorDB = {} end
    local settings = GamepadCrosshairColorDB
    for key, defaultValue in pairs(addon.DEFAULTS) do
        if settings[key] == nil then settings[key] = defaultValue end
    end
    return settings
end

-- "RRGGBBAA" (or "RRGGBB", opaque; a leading # is fine) as 0-1 red, green, blue,
-- alpha and the upper-case "RRGGBBAA", or nil.
function addon.ParseColor(text)
    if type(text) ~= "string" then return nil end
    local hex = text:gsub("^#", ""):upper()
    if #hex == 6 then hex = hex .. "FF" end
    if not hex:match("^%x%x%x%x%x%x%x%x$") then return nil end
    local channels = {}
    for i = 1, 4 do channels[i] = tonumber(hex:sub(i * 2 - 1, i * 2), 16) / 255 end
    return channels[1], channels[2], channels[3], channels[4], hex
end

function addon.FormatColor(red, green, blue, alpha)
    local function byte(value) return math.floor(math.max(0, math.min(1, value or 1)) * 255 + 0.5) end
    return string.format("%02X%02X%02X%02X", byte(red), byte(green), byte(blue), byte(alpha))
end

-- The saved color, "RRGGBBAA" (white if the saved text is broken).
function addon.Color()
    local _, _, _, _, hex = addon.ParseColor(addon.Settings().color)
    return hex or addon.DEFAULTS.color
end

local function crosshairDot()
    local crosshairFrame = _G.GamepadReticle
    local dot = type(crosshairFrame) == "table" and crosshairFrame.Icons and crosshairFrame.Icons.StandardIcon
    if type(dot) ~= "table" or type(dot.SetVertexColor) ~= "function" then return nil end
    return dot
end

local originalColor   -- the dot's own color, read before the first tint: { red, green, blue, alpha }

-- Tints the dot with the saved color, or puts its own color back when switched off.
function addon.ColorCrosshair()
    local dot = crosshairDot()
    if not dot then return end
    if not originalColor then
        local red, green, blue, alpha = 1, 1, 1, 1
        if type(dot.GetVertexColor) == "function" then red, green, blue, alpha = dot:GetVertexColor() end
        originalColor = { red or 1, green or 1, blue or 1, alpha or 1 }
    end
    if addon.Settings().enabled then
        dot:SetVertexColor(addon.ParseColor(addon.Color()))
    else
        dot:SetVertexColor(originalColor[1], originalColor[2], originalColor[3], originalColor[4])
    end
end

-- Saves and shows a new color. False (and nothing changed) if the text isn't a color.
function addon.SetColor(text)
    local red, _, _, _, hex = addon.ParseColor(text)
    if not red then return false end
    addon.Settings().color = hex
    addon.ColorCrosshair()
    return true
end

-- The opacity alone, 0 to 1: the color kept.
function addon.Opacity()
    local _, _, _, alpha = addon.ParseColor(addon.Color())
    return alpha
end

function addon.SetOpacity(alpha)
    local red, green, blue = addon.ParseColor(addon.Color())
    addon.SetColor(addon.FormatColor(red, green, blue, math.max(0, math.min(1, tonumber(alpha) or 1))))
end
