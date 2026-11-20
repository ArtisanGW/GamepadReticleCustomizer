-- Colors as "RRGGBBAA" text (hex, alpha last): the crosshair's ("color") and its
-- border's ("borderColor"). Each is saved under its key in the settings; a change
-- redraws the crosshair (Crosshair.lua).
local _, addon = ...

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

-- The saved color under a key ("color" by default), "RRGGBBAA"; its default if broken.
function addon.Color(key)
    key = key or "color"
    local _, _, _, _, hex = addon.ParseColor(addon.Settings()[key])
    return hex or addon.DEFAULTS[key]
end

-- Saves and shows a new color. False (and nothing changed) if the text isn't a color.
function addon.SetColor(text, key)
    local red, _, _, _, hex = addon.ParseColor(text)
    if not red then return false end
    addon.Settings()[key or "color"] = hex
    addon.UpdateCrosshair()
    return true
end

-- The opacity alone, 0 to 1, the color kept.
function addon.Opacity(key)
    local _, _, _, alpha = addon.ParseColor(addon.Color(key))
    return alpha
end

function addon.SetOpacity(alpha, key)
    local red, green, blue = addon.ParseColor(addon.Color(key))
    addon.SetColor(addon.FormatColor(red, green, blue, math.max(0, math.min(1, tonumber(alpha) or 1))), key)
end
