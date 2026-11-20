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
local _, addon = ...
_G.GamepadReticleCustomizer = addon

--   enabled:       draw the customized reticle (off: the game's own dot back).
--   icon:          the reticle's shape, always shown (Icons.lua): "dot", the game's
--                  own, or a Jiberish Fabled Icons reticle shape.
--   color:         the reticle's color, 32 bits as "RRGGBBAA" (hex, alpha last).
--   size:          its width and height, in the reticle's own units (the game's dot is 4).
--   dotSize, shapeSize: the size each kind had when last left (the dot's, a shape's),
--                  brought back when switching to it.
--   friendlyPlayerIcon, otherFactionIcon, friendlyNpcIcon, neutralNpcIcon, enemyNpcIcon:
--                  what shows instead of the reticle on each kind of target
--                  (addon.TARGET_KINDS; its choices: Icons.TargetList): "none" (the
--                  reticle stays), its own icon ("class", "faction", "job", "dots",
--                  "swords"), a raid marker or one of the game's icons. Icons keep their
--                  own colors.
--   friendlyClassStyle, otherClassStyle: the class icons' style for your faction's
--                  players and the other's (Icons.lua): "game" or a Jiberish Fabled
--                  Icons class sheet.
--   iconSize:      the icon's width and height.
--   borderSize:    how far the border reaches out around either (0: no border).
--   borderColor:   the border's color, "RRGGBBAA".
addon.DEFAULTS = { enabled = true, icon = "dot", color = "FFFFFFFF", size = 4, dotSize = 4, shapeSize = 32, friendlyClassStyle = "game", otherClassStyle = "game", iconSize = 32,
    friendlyPlayerIcon = "none", otherFactionIcon = "none", friendlyNpcIcon = "none", neutralNpcIcon = "none",
    enemyNpcIcon = "none",
    borderSize = 0, borderColor = "000000FF" }
-- The kinds of target, in the settings page's order: { key (its setting), label, tooltip }.
addon.TARGET_KINDS = {
    { key = "friendlyPlayerIcon", label = "Your faction", tooltip = "Players of your faction.", classStyleKey = "friendlyClassStyle" },
    { key = "otherFactionIcon", label = "Other faction", tooltip = "Players of the other faction, PvP flagged or not.",
        classStyleKey = "otherClassStyle" },
    { key = "friendlyNpcIcon", label = "Friendly NPCs", tooltip = "Friendly NPCs, like vendors, trainers and guards." },
    { key = "neutralNpcIcon", label = "Neutral NPCs", tooltip = "Neutral NPCs and critters." },
    { key = "enemyNpcIcon", label = "Enemy NPCs", tooltip = "The NPCs you fight." },
}
-- The class icon style for a kind of target: the other faction's for theirs, else yours.
function addon.ClassStyleFor(settings, kindKey)
    if kindKey == "otherFactionIcon" then return settings.otherClassStyle end
    return settings.friendlyClassStyle
end

-- A player row's faction name ("Horde"), or nil without a faction.
local function rowFactionName(kind)
    local playerFaction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
    local other = { Horde = "Alliance", Alliance = "Horde" }
    if not other[playerFaction] then return nil end
    local faction = kind.key == "friendlyPlayerIcon" and playerFaction or other[playerFaction]
    return _G["FACTION_" .. faction:upper()] or faction
end

-- A player row's class icon style label ("Horde class icons"; without a faction,
-- "Your class icons" and "Other class icons").
function addon.ClassStyleLabel(kind)
    local factionName = rowFactionName(kind)
    if factionName then return factionName .. " class icons" end
    return kind.key == "friendlyPlayerIcon" and "Your class icons" or "Other class icons"
end

-- A kind's row label: the player rows say whose players, by faction ("Horde
-- players" for yours when you're Horde); without a faction, "Your faction" and
-- "Other faction".
function addon.KindLabel(kind)
    local factionName = kind.classStyleKey and rowFactionName(kind)
    return factionName and (factionName .. " players") or kind.label
end
addon.SIZE_MIN, addon.SIZE_MAX, addon.SIZE_STEP = 2, 64, 1
addon.BORDER_MIN, addon.BORDER_MAX, addon.BORDER_STEP = 0, 10, 1


function addon.Settings()
    if type(GamepadReticleCustomizerDB) ~= "table" then GamepadReticleCustomizerDB = {} end
    local settings = GamepadReticleCustomizerDB
    -- A shape setting holding a marker or a game icon: that's an icon on a target.
    if settings.targetIcon == nil and settings.icon ~= nil and not addon.Icons.IsReticleShape(settings.icon) then
        settings.targetIcon, settings.icon = settings.icon, "dot"
    end
    -- A custom texture path: none.
    if settings.targetIcon == "custom" then settings.targetIcon = "none" end
    settings.customTexture = nil
    -- One class icon style for both factions: copied to each.
    if settings.classStyle ~= nil then
        settings.friendlyClassStyle, settings.otherClassStyle = settings.classStyle, settings.classStyle
        settings.classStyle = nil
    end
    -- One choice for every target ("targetIcon"): copied to each kind it fits.
    if settings.targetIcon ~= nil then
        local choice = settings.targetIcon
        if choice == "class" then
            settings.friendlyPlayerIcon, settings.otherFactionIcon = "class", "class"
        elseif choice ~= "none" then
            for _, kind in ipairs(addon.TARGET_KINDS) do settings[kind.key] = choice end
        end
        settings.targetIcon = nil
    end
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
