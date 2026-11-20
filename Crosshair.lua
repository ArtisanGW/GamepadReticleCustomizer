-- Draws the customized crosshair on the game's own: its shape (Icons.lua) at its
-- size and color, or while you have a target the icon chosen for one, with a
-- border behind either (the same picture, larger, in the border color).
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

-- What's drawn now, for the tests and /gcc debug: { icon, texture or atlas, size, borderSize } or nil.
local drawn
function Crosshair.Drawn() return drawn end
function Crosshair.Layer() return layer end
function Crosshair.GameDotAlpha() return gameDotAlpha end

-- What to draw now: the icon for a target while you have one whose nameplate is
-- on screen (and it can be drawn), else the crosshair's shape. A target without a
-- nameplate (a vendor, a guard or a minion with their nameplates off, as by
-- default, or one off screen) keeps the crosshair: the icon follows what your
-- nameplate settings show. { icon, texture or atlas, size, tinted }.
function Crosshair.Choose(settings, target)
    local targetIcon = settings.targetIcon
    if target.exists and target.hasNameplate and targetIcon ~= "none" then
        local iconSize = addon.Clamp(settings.iconSize, addon.SIZE_MIN, addon.SIZE_MAX, addon.DEFAULTS.iconSize)
        if targetIcon == "class" then
            local classLook = target.isPlayer and addon.Icons.ClassLook(target.classFile, settings.classStyle)
            if classLook then
                return { icon = "class", atlas = classLook.atlas, texture = classLook.texture, texCoord = classLook.texCoord,
                    size = iconSize, tinted = false }
            end
        else
            local texture = addon.Icons.Texture(targetIcon, settings.customTexture)
            if texture then return { icon = targetIcon, texture = texture, size = iconSize, tinted = false } end
        end
    end
    -- The crosshair: a shape that can't be drawn now (a Jiberish one without the
    -- addon) falls back to the game's dot.
    local icon = settings.icon
    local texture = addon.Icons.IsCrosshairShape(icon) and addon.Icons.Texture(icon)
    if not texture then icon, texture = "dot", addon.Icons.GAME_DOT_TEXTURE end
    return { icon = icon, texture = texture, size = addon.Clamp(settings.size, addon.SIZE_MIN, addon.SIZE_MAX,
        addon.DEFAULTS.size), tinted = true }
end

-- A texture's picture: an atlas, or a file shown whole or in part (a cell of a
-- sheet); after an atlas, the texture coordinates are reset.
local function setPicture(texture, look)
    if look.atlas then
        texture:SetAtlas(look.atlas)
    else
        texture:SetTexture(look.texture)
        local coords = look.texCoord or { 0, 1, 0, 1 }
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
end

-- Paints a look (from Choose) on a shape texture and the border texture behind it,
-- in the saved colors and border size (also the settings page's preview).
-- Returns the border size used.
function Crosshair.Paint(shape, border, look)
    local borderSize = addon.Clamp(addon.Settings().borderSize, addon.BORDER_MIN, addon.BORDER_MAX, 0)
    setPicture(shape, look)
    shape:SetSize(look.size, look.size)
    if look.tinted then
        shape:SetVertexColor(addon.ParseColor(addon.Color("color")))
    else
        shape:SetVertexColor(1, 1, 1, 1)   -- an icon keeps its own colors
    end
    if borderSize > 0 then
        setPicture(border, look)
        border:SetSize(look.size + 2 * borderSize, look.size + 2 * borderSize)
        border:SetVertexColor(addon.ParseColor(addon.Color("borderColor")))
        border:Show()
    else
        border:Hide()
    end
    return borderSize
end

-- Draws the crosshair from the settings and the target, or puts the game's dot
-- back when off. Runs on login, on each setting change and when the target changes.
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
        if addon.Preview then addon.Preview.Refresh() end
        return
    end

    local look = Crosshair.Choose(settings, addon.TargetInfo())
    local borderSize = Crosshair.Paint(layer.shape, layer.border, look)
    layer:Show()
    dot:SetAlpha(0)
    drawn = { icon = look.icon, texture = look.texture, atlas = look.atlas, texCoord = look.texCoord, size = look.size,
        borderSize = borderSize }
    if addon.Preview then addon.Preview.Refresh() end
end
