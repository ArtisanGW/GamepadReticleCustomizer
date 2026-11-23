-- Draws the customized reticle on the game's own: its shape (Icons.lua) at its
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

local Reticle = {
    GRAY = { 0.6, 0.6, 0.6 },   -- a colored white icon (the paw) out of reach
}
addon.Reticle = Reticle

local layer          -- our frame: layer.shape, layer.border
local gameDotAlpha   -- the game's dot's own alpha, read before we first hid it

local function gameDot()
    local reticleFrame = _G.GamepadReticle
    local dot = type(reticleFrame) == "table" and reticleFrame.Icons and reticleFrame.Icons.StandardIcon
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
    -- Drawn again whenever the reticle is moved (onto a nameplate or back): a
    -- post-hook, the game's own SetPoint runs untouched.
    if type(hooksecurefunc) == "function" and type(GamepadReticle.SetPoint) == "function" then
        hooksecurefunc(GamepadReticle, "SetPoint", function() addon.UpdateReticle() end)
    end
end

-- What's drawn now: { icon, texture or atlas, size, borderSize } or nil.
local drawn
function Reticle.Drawn() return drawn end
function Reticle.Layer() return layer end
function Reticle.GameDotAlpha() return gameDotAlpha end

-- What to draw now: the icon chosen for the target's kind while you have one whose nameplate is
-- on screen and the reticle sits on a nameplate (and it can be drawn), else the
-- reticle's shape. A target without a nameplate (a vendor, a guard or a minion
-- with their nameplates off, as by default, or one off screen) keeps the reticle:
-- the icon follows what your nameplate settings show. So does a reticle left in
-- the middle of the screen, where the game puts it: an icon there would mark
-- nothing. { icon, texture or atlas, size, tinted, color (an icon drawn in color), gray }.
function Reticle.Choose(settings, target)
    local kindKey = addon.TargetKindKey(target)
    local choice = kindKey and settings[kindKey] or "none"
    if target.hasNameplate and target.reticleOnNameplate and choice ~= "none" then
        local look = addon.Icons.TargetLook(choice, target, addon.ClassStyleFor(settings, kindKey))
        if look then
            local iconSize = addon.Clamp(settings.iconSize, addon.SIZE_MIN, addon.SIZE_MAX, addon.DEFAULTS.iconSize)
            return { icon = choice, atlas = look.atlas, texture = look.texture, texCoord = look.texCoord,
                cursorUnit = look.cursorUnit, size = iconSize, tinted = false, color = look.color,
                gray = addon.Range and addon.Range.IconGray(choice) or false }   -- Range.lua
        end
    end
    -- The reticle: a shape that can't be drawn now (a Jiberish one without the
    -- addon) falls back to the game's dot.
    local icon = settings.icon
    local texture = addon.Icons.IsReticleShape(icon) and addon.Icons.Texture(icon)
    if not texture then icon, texture = "dot", addon.Icons.GAME_DOT_TEXTURE end
    return { icon = icon, texture = texture, size = addon.Clamp(settings.size, addon.SIZE_MIN, addon.SIZE_MAX,
        addon.DEFAULTS.size), tinted = true }
end

-- A texture's picture: a file shown whole or in part (a cell of a sheet, an
-- atlas's cell), its coordinates always set; or, with no file, an atlas, after
-- resetting the coordinates a previous cell left.
local function setPicture(texture, look)
    if look.cursorUnit then
        -- A unit's own interaction icon, as the game sets it on its nameplates
        -- (Blizzard_NamePlates.lua:201, forever branch), but never the controller's
        -- interact button the game swaps in once you're in range (preferGamepadIcon).
        texture:SetTexCoord(0, 1, 0, 1)
        SetUnitCursorTexture(texture, look.cursorUnit, nil, nil, false)
    elseif look.texture then
        texture:SetTexture(look.texture)
        local coords = look.texCoord or { 0, 1, 0, 1 }
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetAtlas(look.atlas)
    end
end

-- Paints a look (from Choose) on a shape texture and the border texture behind it,
-- in the saved colors and border size (also the settings page's preview).
-- zoom (optional, 1 by default): the preview's magnified view, size and border alike.
-- Returns the border size used (unzoomed).
function Reticle.Paint(shape, border, look, zoom)
    zoom = zoom or 1
    local borderSize = addon.Clamp(addon.Settings().borderSize, addon.BORDER_MIN, addon.BORDER_MAX, 0)
    setPicture(shape, look)
    shape:SetSize(look.size * zoom, look.size * zoom)
    if look.tinted then
        shape:SetVertexColor(addon.ParseColor(addon.Color("color")))
    elseif look.color then
        local gray = look.gray and Reticle.GRAY or look.color   -- a white icon drawn in color (the paw)
        shape:SetVertexColor(gray[1], gray[2], gray[3], 1)
    else
        shape:SetVertexColor(1, 1, 1, 1)   -- an icon keeps its own colors
    end
    shape:SetDesaturated(look.gray == true)   -- out of reach (Range.lua)
    if borderSize > 0 then
        setPicture(border, look)
        border:SetSize((look.size + 2 * borderSize) * zoom, (look.size + 2 * borderSize) * zoom)
        border:SetVertexColor(addon.ParseColor(addon.Color("borderColor")))
        border:Show()
    else
        border:Hide()
    end
    return borderSize
end

-- The game's own interaction icon on the target's nameplate (its SoftTargetFrame,
-- Blizzard_NamePlates.xml:261, forever branch: a quest's "!", a vendor's bag, the
-- controller's button) sits where the reticle goes on a target: while our icon is
-- drawn there, the game's is made see-through (its alpha, kept and put back), so
-- only one shows. The reticle's own shape leaves it as it is.
local hiddenIconSpot, hiddenIconSpotAlpha
local function showGameIcon()
    if hiddenIconSpot then hiddenIconSpot:SetAlpha(hiddenIconSpotAlpha or 1) end
    hiddenIconSpot, hiddenIconSpotAlpha = nil, nil
end
local function hideTargetsGameIcon()
    local namePlates = _G.C_NamePlate
    local succeeded, nameplate = false, nil
    if type(namePlates) == "table" and type(namePlates.GetNamePlateForUnit) == "function" then
        succeeded, nameplate = pcall(namePlates.GetNamePlateForUnit, "target")
    end
    local unitFrame = succeeded and type(nameplate) == "table" and nameplate.UnitFrame
    local iconSpot = type(unitFrame) == "table" and unitFrame.SoftTargetFrame
    if type(iconSpot) ~= "table" or type(iconSpot.SetAlpha) ~= "function"
        or (type(iconSpot.IsForbidden) == "function" and iconSpot:IsForbidden()) then return showGameIcon() end
    if iconSpot == hiddenIconSpot then return end
    showGameIcon()
    hiddenIconSpot, hiddenIconSpotAlpha = iconSpot, iconSpot:GetAlpha()
    iconSpot:SetAlpha(0)
end

-- Draws the reticle from the settings and the target, or puts the game's dot
-- back when off. Runs on login, on each setting change and when the target changes.
function addon.UpdateReticle()
    if addon.jobIconPending then return end   -- a job icon's draw is on its way (GamepadReticleCustomizer.lua)
    local dot = gameDot()
    if not dot then return end
    if not layer then buildLayer(dot) end
    if gameDotAlpha == nil then gameDotAlpha = dot:GetAlpha() end

    local settings = addon.Settings()
    if not settings.enabled then
        layer:Hide()
        dot:SetAlpha(gameDotAlpha)
        showGameIcon()
        drawn = nil
        if addon.Preview then addon.Preview.Refresh() end
        return
    end

    local look = Reticle.Choose(settings, addon.TargetInfo())
    if look.tinted then showGameIcon() else hideTargetsGameIcon() end   -- an icon on the target: one at a time
    local borderSize = Reticle.Paint(layer.shape, layer.border, look)
    layer:Show()
    dot:SetAlpha(0)
    drawn = { icon = look.icon, texture = look.texture, atlas = look.atlas, texCoord = look.texCoord, size = look.size,
        cursorUnit = look.cursorUnit, gray = look.gray,
        borderSize = borderSize }
    if addon.Range then addon.Range.Watch(look.icon, look.gray) end
    if addon.Preview then addon.Preview.Refresh() end
end
