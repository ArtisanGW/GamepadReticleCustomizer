-- What the reticle can look like.
--
-- The reticle's shapes, always shown (setting "icon"):
--   "dot"             the game's own dot (its texture, GamepadReticle.xml:94)
--   "jiberish:<name>" Jiberish Fabled Icons' reticle shapes, offered only when
--                     that addon is installed (enabled or not: the game reads the
--                     files from its folder either way). Named here only as text:
--                     nothing calls it or depends on it, nothing is copied, and
--                     its shapes are credited (its license asks for that).
-- The icons shown instead on a target (a setting per kind of target, addon.TARGET_KINDS):
--   "none"            none: the reticle stays
--   "class"           a player target's class, in a class icon style (setting
--                     "friendlyClassStyle" or "otherClassStyle"): "game" (the game's classicon-<class> atlases), or
--                     "jiberish:<style>", a Jiberish Fabled Icons class sheet when installed
--   "faction"         a player's faction badge
--   "job"             a friendly NPC's own interaction icon (buy, train, repair, flight...),
--                     as the game shows it; the reticle when there's nothing to interact
--                     with; a speech bubble when the game doesn't say
--   "dots"            the game's gray "..." bubble (neutral NPCs)
--   "paw"             our own paw (Media/paw.png), yellow like neutral (neutral NPCs),
--                     gray while none of your spells reach the target (Range.lua)
--   "shield"          the game's neutral shield (neutral NPCs), gray out of reach too
--   "swords"          a sword, the game's attack cursor (enemy and neutral NPCs),
--                     gray while none of your spells reach the target (Range.lua)
--   "marker1".."8"    the game's raid target markers: star, circle, diamond,
--                     triangle, moon, square, cross, skull
--   "icon:<key>"      one of GAME_ICONS, a hand-picked set of the game's own icons
-- (No icon picker and no texture path: the game's picker, created by addon code,
-- breaks the controller's navigation; a path is too technical.)
local _, addon = ...

local Icons = {
    GAME_DOT_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_",
    RAID_MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" },
    CLASS_ATLAS_PREFIX = "classicon-",
    -- Icons for kinds of target: the game's own, each with a file to fall back on
    -- should this client not have the atlas.
    FACTION_ATLASES = { Alliance = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", Horde = "UI-HUD-UnitFrame-Player-PVP-HordeIcon" },
    KIND_ICONS = {
        -- the game's attack cursor (its atlas Crosshair_PVP_128 is the PvP cursor, a shield)
        swords = { file = "Interface\\Cursor\\Attack" },
        -- white, drawn in color: the game's tiny pet paw atlas blurs at reticle sizes
        paw = { file = "Interface\\AddOns\\GamepadReticleCustomizer\\Media\\paw.png", color = { 1, 0.82, 0 } },
        shield = { atlas = "honorsystem-portrait-neutral", file = "Interface\\AddOns\\GamepadReticleCustomizer\\Media\\paw.png" },
        -- a gray "..." bubble: the game's quest-in-progress icon (QuestUtils.lua:199)
        dots = { atlas = "SideInProgressquesticon", file = "Interface\\GossipFrame\\IncompleteQuestIcon" },
        talk = { atlas = "Crosshair_Speak_128", file = "Interface\\GossipFrame\\GossipGossipIcon" }, -- a speech bubble
    },
    -- The game's own icons offered on a target: in the game since its first years.
    GAME_ICONS = {
        { key = "scope", name = "Sniper scope", file = "Interface\\Icons\\Ability_Hunter_SniperShot" },
        { key = "mark", name = "Hunter's mark", file = "Interface\\Icons\\Ability_Hunter_MarkedForDeath" },
        { key = "weakspot", name = "Weak spot", file = "Interface\\Icons\\Ability_Rogue_FindWeakness" },
        { key = "skull", name = "Skull", file = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
        { key = "eye", name = "Eye", file = "Interface\\Icons\\INV_Misc_Eye_01" },
        { key = "charge", name = "Charge", file = "Interface\\Icons\\Ability_Warrior_Charge" },
        { key = "blades", name = "Crossed blades", file = "Interface\\Icons\\Ability_DualWield" },
        { key = "fire", name = "Fire", file = "Interface\\Icons\\Spell_Fire_FlameBolt" },
        { key = "frost", name = "Frost", file = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
        { key = "nature", name = "Nature", file = "Interface\\Icons\\Spell_Nature_StarFall" },
        { key = "shadow", name = "Shadow", file = "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
        { key = "holy", name = "Holy", file = "Interface\\Icons\\Spell_Holy_HolyBolt" },
    },
    JIBERISH_ADDON = "JiberishIcons",
    JIBERISH_FOLDER = "Interface\\AddOns\\JiberishIcons\\Media\\Crosshair\\",
    JIBERISH_SHAPES = { "circle", "diamond", "plus", "splitplus", "splitx", "square", "triangle", "x" },
    JIBERISH_SHAPE_NAMES = { circle = "Circle", diamond = "Diamond", plus = "Plus", splitplus = "Split plus",
        splitx = "Split X", square = "Square", triangle = "Triangle", x = "X" },
    -- The slider shows the chosen name on its right, about this many characters
    -- before it's cut: every label fits.
    LABEL_MAX_LENGTH = 22,
    JIBERISH_WEIGHTS = { "bold", "thin" },
    JIBERISH_FILE_SIZE = 128,   -- each shape comes in 32, 64, 128 and 256 px
    JIBERISH_CREDIT = "Shapes from Jiberish Fabled Icons",
    JIBERISH_CLASS_FOLDER = "Interface\\AddOns\\JiberishIcons\\Media\\Class\\",
    -- Its class sheets (files and names as it lists them).
    JIBERISH_CLASS_STYLES = {
        { file = "fabled", name = "Fabled" }, { file = "fabledclass", name = "Fabled Class" },
        { file = "fabledpixels", name = "Fabled Pixels" }, { file = "fabledpixelsv2", name = "Fabled Pixels v2" },
        { file = "fabledcore", name = "Fabled Core" }, { file = "fableddimension", name = "Fabled Dimension" },
        { file = "fabledmyth", name = "Fabled Myth" }, { file = "fabledrealm", name = "Fabled Realm" },
        { file = "fabledrealmv2", name = "Fabled Realm v2" }, { file = "fabledregalia", name = "Fabled Regalia" },
        { file = "intothevoid", name = "Into The VOID" },
    },
    -- Where each class sits on a sheet: { column, row } of an 8 by 8 grid (all its
    -- class sheets share this layout).
    JIBERISH_CLASS_GRID = {
        WARRIOR = { 0, 0 }, MAGE = { 1, 0 }, ROGUE = { 2, 0 }, DRUID = { 3, 0 }, EVOKER = { 4, 0 },
        HUNTER = { 0, 1 }, SHAMAN = { 1, 1 }, PRIEST = { 2, 1 }, WARLOCK = { 3, 1 },
        PALADIN = { 0, 2 }, DEATHKNIGHT = { 1, 2 }, MONK = { 2, 2 }, DEMONHUNTER = { 3, 2 },
    },
    JIBERISH_CLASS_GRID_CELLS = 8,
    JIBERISH_LINK = "https://www.curseforge.com/wow/addons/jiberish-fabled-icons",
}
addon.Icons = Icons

-- Jiberish Fabled Icons for this character: "missing" (not installed),
-- "disabled" (installed, turned off in the AddOns list) or "enabled". Its shapes
-- and styles are offered only when enabled. Not whether it's loaded: this addon
-- loads before it. First whether it can load and why not (GetAddOnInfo: loadable,
-- reason "DISABLED"); then its switch for this character (GetAddOnEnableState, 0
-- is off; AddOnsDocumentation.lua:98-130, forever branch). The switch alone, with
-- UnitName, doesn't see it turned off.
-- The key the game's AddOns list uses for this character: the player's GUID, not
-- the name (Blizzard_AddOnList/AddonList.lua:12-24, forever branch). With the name,
-- EnableAddOn switches on a "character" the game never reads.
function Icons.CharacterKey()
    return type(UnitGUID) == "function" and UnitGUID("player") or nil
end

function Icons.JiberishState()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return "missing" end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, Icons.JIBERISH_ADDON)
    if not (succeeded and exists == true) then return "missing" end
    if type(addOns.GetAddOnInfo) == "function" then
        local infoSucceeded, _, _, _, loadable, reason = pcall(addOns.GetAddOnInfo, Icons.JIBERISH_ADDON)
        if infoSucceeded and (reason == "DISABLED" or (loadable == false and reason ~= "DEMAND_LOADED")) then
            return "disabled"
        end
    end
    if type(addOns.GetAddOnEnableState) == "function" then
        local stateSucceeded, state = pcall(addOns.GetAddOnEnableState, Icons.JIBERISH_ADDON, Icons.CharacterKey())
        if stateSucceeded and tonumber(state) == 0 then return "disabled" end
    end
    return "enabled"
end

-- Whether its shapes and styles can be offered and drawn now.
function Icons.JiberishEnabled() return Icons.JiberishState() == "enabled" end

-- Whether an id is one of the reticle's shapes (not an icon for a target).
function Icons.IsReticleShape(iconId)
    return iconId == "dot" or tostring(iconId):match("^jiberish:%l+%-%l+$") ~= nil
end

-- The reticle's shapes on offer now, in order: { id, label }.
function Icons.ReticleList()
    local list = { { id = "dot", label = "Default dot" } }
    if Icons.JiberishEnabled() then
        for _, shape in ipairs(Icons.JIBERISH_SHAPES) do
            for _, weight in ipairs(Icons.JIBERISH_WEIGHTS) do
                list[#list + 1] = { id = "jiberish:" .. shape .. "-" .. weight,
                    label = Icons.JIBERISH_SHAPE_NAMES[shape] .. " (" .. weight .. ")" }
            end
        end
    end
    return list
end

-- Each kind of target's own choices, after None (addon.TARGET_KINDS' keys).
Icons.KIND_CHOICES = {
    friendlyPlayerIcon = { { id = "faction", label = "Faction" }, { id = "class", label = "Class" } },
    otherFactionIcon = { { id = "faction", label = "Faction" }, { id = "class", label = "Class" } },
    friendlyNpcIcon = { { id = "job", label = "Their job" } },
    neutralNpcIcon = { { id = "dots", label = "Gray dots" }, { id = "paw", label = "Paw" }, { id = "shield", label = "Shield" },
        { id = "swords", label = "Sword" } },
    enemyNpcIcon = { { id = "swords", label = "Sword" } },
}

-- A kind of target's choices, in order: None, its own, the raid markers, the
-- game's icons. { id, label }.
function Icons.TargetList(kindKey)
    local list = { { id = "none", label = "None" } }
    for _, choice in ipairs(Icons.KIND_CHOICES[kindKey] or {}) do list[#list + 1] = choice end
    for index = 1, 8 do
        list[#list + 1] = { id = "marker" .. index,
            label = "Raid marker: " .. (_G["RAID_TARGET_" .. index] or Icons.RAID_MARKER_NAMES[index]) }
    end
    for _, gameIcon in ipairs(Icons.GAME_ICONS) do
        list[#list + 1] = { id = "icon:" .. gameIcon.key, label = "Icon: " .. gameIcon.name }
    end
    return list
end

-- The texture path an id draws, or nil if there's none (an unknown id, a
-- Jiberish shape without the addon; "none" and "class" aren't textures).
function Icons.Texture(iconId)
    if iconId == "dot" then return Icons.GAME_DOT_TEXTURE end
    local markerIndex = tonumber(tostring(iconId):match("^marker(%d)$"))
    if markerIndex and markerIndex >= 1 and markerIndex <= 8 then return Icons.RAID_MARKER_TEXTURE .. markerIndex end
    local jiberishName = tostring(iconId):match("^jiberish:(%l+%-%l+)$")
    if jiberishName and Icons.JiberishEnabled() then
        return Icons.JIBERISH_FOLDER .. jiberishName .. "-" .. Icons.JIBERISH_FILE_SIZE
    end
    local gameIconKey = tostring(iconId):match("^icon:(%l+)$")
    for _, gameIcon in ipairs(Icons.GAME_ICONS) do
        if gameIcon.key == gameIconKey then return gameIcon.file end
    end
    return nil
end

-- The class icon styles on offer now, in order: { id, label }.
function Icons.ClassStyleList()
    local list = { { id = "game", label = "Default" } }
    if Icons.JiberishEnabled() then
        for _, style in ipairs(Icons.JIBERISH_CLASS_STYLES) do
            list[#list + 1] = { id = "jiberish:" .. style.file, label = style.name }
        end
    end
    return list
end

-- A class's icon in a style: { atlas } or { texture, texCoord = { left, right, top, bottom } },
-- or nil. A Jiberish style without the addon, or a class not on its sheet, falls
-- back to the game's icon.
function Icons.ClassLook(classFile, style)
    local file = tostring(style or ""):match("^jiberish:(%l[%l%d]*)$")
    local cell = Icons.JIBERISH_CLASS_GRID[classFile or ""]
    if file and cell and Icons.JiberishEnabled() then
        local cells = Icons.JIBERISH_CLASS_GRID_CELLS
        return { texture = Icons.JIBERISH_CLASS_FOLDER .. file,
            texCoord = { cell[1] / cells, (cell[1] + 1) / cells, cell[2] / cells, (cell[2] + 1) / cells } }
    end
    return Icons.AtlasLook(Icons.ClassAtlas(classFile))
end

-- An atlas as a look, or nil if this client doesn't have it: its file and cell
-- (C_Texture.GetAtlasInfo, TextureUtilsDocumentation.lua:207, forever branch),
-- drawn as a Jiberish Fabled Icons cell is: switching from a Jiberish style with
-- SetAtlas keeps that style's cell.
function Icons.AtlasLook(atlas)
    local textures = _G.C_Texture
    if type(atlas) ~= "string" or type(textures) ~= "table" or type(textures.GetAtlasInfo) ~= "function" then return nil end
    local succeeded, info = pcall(textures.GetAtlasInfo, atlas)
    if not (succeeded and info) then return nil end
    local file = info.file or info.filename
    if file then
        return { atlas = atlas, texture = file,
            texCoord = { info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord } }
    end
    return { atlas = atlas }
end

-- The game's interaction icon for a unit (what it shows over it on a controller):
-- "icon" (buy, train, repair, flight...), "nothing" (its plain pointer,
-- "Crosshair_Point_64": nothing to interact with) or "unknown" (no answer); then
-- the icon's name ("Cursor Crosshair_Quest_64").
-- SetUnitCursorTexture answers on a hidden texture of ours (UnitDocumentation.lua:595,
-- forever branch).
local probe
function Icons.InteractionIcon(unit)
    if type(SetUnitCursorTexture) ~= "function" then return "unknown" end
    if not probe then
        local holder = CreateFrame("Frame")
        holder:Hide()
        probe = holder:CreateTexture()
    end
    local succeeded, hasIcon = pcall(SetUnitCursorTexture, probe, unit, nil, nil, false)
    if not (succeeded and hasIcon == true) then return "unknown" end
    local name = type(probe.GetTexture) == "function" and tostring(probe:GetTexture()) or ""
    if name:find("Crosshair_Point", 1, true) then return "nothing", name end
    return "icon", name
end

-- One of KIND_ICONS: its atlas, else its file.
local function kindIcon(key)
    local entry = Icons.KIND_ICONS[key]
    return Icons.AtlasLook(entry.atlas) or { texture = entry.file, color = entry.color }
end

-- What a choice shows on a target (from addon.TargetInfo): { atlas } or
-- { texture, texCoord }, or nil to keep the reticle (a class choice on an NPC,
-- or an icon this client can't draw).
function Icons.TargetLook(choice, target, classStyle)
    if choice == "class" then return target.isPlayer and Icons.ClassLook(target.classFile, classStyle) or nil end
    if choice == "faction" then return Icons.AtlasLook(Icons.FACTION_ATLASES[target.faction or ""]) end
    if choice == "job" then
        local interaction = Icons.InteractionIcon("target")
        if interaction == "icon" then return { cursorUnit = "target" } end
        if interaction == "nothing" then return nil end   -- nothing to interact with: the reticle
        return kindIcon("talk")
    end
    if Icons.KIND_ICONS[choice] then return kindIcon(choice) end
    local texture = Icons.Texture(choice)
    return texture and { texture = texture } or nil
end

-- The game's atlas for a class ("WARRIOR" -> "classicon-warrior"), or nil if
-- this client doesn't have it.
function Icons.ClassAtlas(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    local atlas = Icons.CLASS_ATLAS_PREFIX .. classFile:lower()
    local textures = _G.C_Texture
    if type(textures) ~= "table" or type(textures.GetAtlasInfo) ~= "function" then return nil end
    local succeeded, info = pcall(textures.GetAtlasInfo, atlas)
    return (succeeded and info) and atlas or nil
end
