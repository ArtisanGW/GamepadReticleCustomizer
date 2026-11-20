-- Draws the customized crosshair on the game's own: a shape (Icons.lua) at its size
-- and color, with a border behind it (the same shape, larger, in the border color).
--
-- Enhance, don't replace: the drawing is our own frame, a child of the game's
-- GamepadReticle.Icons, so it shows, hides and fades with the game's dot (the game
-- hides Icons while the cursor shows and fades it for the swing timer,
-- GamepadReticle.lua:40-49, forever branch). The game's dot is only made
-- see-through (alpha 0) while ours shows; its own alpha, kept first, is put back
-- when the addon is switched off. Nothing here is protected, so it works in combat.
local _, addon = ...

local Crosshair = {}
addon.Crosshair = Crosshair

local layer          -- our frame: layer.shape, layer.border
local gameDotAlpha   -- the game's dot's own alpha, read before we first hid it

local function gameDot()
    local crosshairFrame = _G.GamepadReticle
    local dot = type(crosshairFrame) == "table" and crosshairFrame.Icons and crosshairFrame.Icons.StandardIcon
    if type(dot) ~= "table" or type(dot.SetAlpha) ~= "function" then return nil end
    return dot
end

local function buildLayer(dot)
    layer = CreateFrame("Frame", nil, GamepadReticle.Icons)
    layer:SetPoint("CENTER", dot, "CENTER")
    layer:SetSize(1, 1)
    layer.border = layer:CreateTexture(nil, "BORDER")
    layer.border:SetPoint("CENTER", layer, "CENTER")
    layer.shape = layer:CreateTexture(nil, "ARTWORK")
    layer.shape:SetPoint("CENTER", layer, "CENTER")
end

-- What's drawn now, for the tests and /gcc debug: { icon, texture, size, borderSize } or nil.
local drawn
function Crosshair.Drawn() return drawn end
function Crosshair.Layer() return layer end
function Crosshair.GameDotAlpha() return gameDotAlpha end

-- Draws the crosshair from the settings, or puts the game's dot back when off.
function addon.UpdateCrosshair()
    local dot = gameDot()
    if not dot then return end
    if not layer then buildLayer(dot) end
    if gameDotAlpha == nil then gameDotAlpha = dot:GetAlpha() end

    local settings = addon.Settings()
    if not settings.enabled then
        layer:Hide()
        dot:SetAlpha(gameDotAlpha)
        drawn = nil
        return
    end

    -- An icon that can't be drawn now (a Jiberish shape without the addon, a
    -- custom one with no path) falls back to the game's dot shape.
    local icon = settings.icon
    local texture = addon.Icons.Texture(icon, settings.customTexture)
    if not texture then icon, texture = "dot", addon.Icons.GAME_DOT_TEXTURE end
    local size = addon.Clamp(settings.size, addon.SIZE_MIN, addon.SIZE_MAX, addon.DEFAULTS.size)
    local borderSize = addon.Clamp(settings.borderSize, addon.BORDER_MIN, addon.BORDER_MAX, 0)

    layer.shape:SetTexture(texture)
    layer.shape:SetSize(size, size)
    layer.shape:SetVertexColor(addon.ParseColor(addon.Color("color")))
    if borderSize > 0 then
        layer.border:SetTexture(texture)
        layer.border:SetSize(size + 2 * borderSize, size + 2 * borderSize)
        layer.border:SetVertexColor(addon.ParseColor(addon.Color("borderColor")))
        layer.border:Show()
    else
        layer.border:Hide()
    end
    layer:Show()
    dot:SetAlpha(0)
    drawn = { icon = icon, texture = texture, size = size, borderSize = borderSize }
end
