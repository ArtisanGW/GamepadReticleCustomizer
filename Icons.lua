-- What the crosshair can look like.
--
-- The crosshair's shapes, always shown (setting "icon"):
--   "dot"             the game's own dot (its texture, GamepadReticle.xml:94)
--   "jiberish:<name>" JiberishUI Fabled Icons' crosshair shapes, offered only when
--                     that addon is installed (enabled or not: the game reads the
--                     files from its folder either way). Named here only as text:
--                     nothing calls it or depends on it, nothing is copied, and
--                     its shapes are credited (its license asks for that).
-- The icons shown instead while you have a target (setting "targetIcon"):
--   "none"            none: the crosshair stays
--   "class"           a player target's class, in a class icon style (setting
--                     "classStyle"): "game" (the game's classicon-<class> atlases), or
--                     "jiberish:<style>", a JiberishUI class sheet when installed
--   "marker1".."8"    the game's raid target markers: star, circle, diamond,
--                     triangle, moon, square, cross, skull
--   "custom"          any texture path you type (the customTexture setting)
local _, addon = ...

local Icons = {
    GAME_DOT_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_",
    RAID_MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" },
    CLASS_ATLAS_PREFIX = "classicon-",
    JIBERISH_ADDON = "JiberishIcons",
    JIBERISH_FOLDER = "Interface\\AddOns\\JiberishIcons\\Media\\Crosshair\\",
    JIBERISH_SHAPES = { "circle", "diamond", "plus", "splitplus", "splitx", "square", "triangle", "x" },
    JIBERISH_WEIGHTS = { "bold", "thin" },
    JIBERISH_FILE_SIZE = 128,   -- each shape comes in 32, 64, 128 and 256 px
    JIBERISH_CREDIT = "Shapes from JiberishUI Fabled Icons",
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

-- Whether JiberishUI Fabled Icons is installed (enabled or not).
function Icons.JiberishInstalled()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, Icons.JIBERISH_ADDON)
    return succeeded and exists == true
end

local function capitalized(text) return (text:gsub("^%l", string.upper)) end

-- Whether an id is one of the crosshair's shapes (not an icon for a target).
function Icons.IsCrosshairShape(iconId)
    return iconId == "dot" or tostring(iconId):match("^jiberish:%l+%-%l+$") ~= nil
end

-- The crosshair's shapes on offer now, in order: { id, label }.
function Icons.CrosshairList()
    local list = { { id = "dot", label = "The game's dot" } }
    if Icons.JiberishInstalled() then
        for _, shape in ipairs(Icons.JIBERISH_SHAPES) do
            for _, weight in ipairs(Icons.JIBERISH_WEIGHTS) do
                list[#list + 1] = { id = "jiberish:" .. shape .. "-" .. weight,
                    label = "Jiberish: " .. capitalized(shape) .. ", " .. weight }
            end
        end
    end
    return list
end

-- The icons for a target, in order: { id, label }.
function Icons.TargetList()
    local list = { { id = "none", label = "None: keep the crosshair" },
        { id = "class", label = "A player's class (others: the crosshair)" } }
    for index = 1, 8 do
        list[#list + 1] = { id = "marker" .. index,
            label = "Raid marker: " .. (_G["RAID_TARGET_" .. index] or Icons.RAID_MARKER_NAMES[index]) }
    end
    list[#list + 1] = { id = "custom", label = "Your own icon (Choose icon...)" }
    return list
end

-- The texture path an id draws, or nil if there's none (an unknown id, a
-- Jiberish shape without the addon, "custom" with no path yet; "none" and
-- "class" aren't textures).
function Icons.Texture(iconId, customTexture)
    if iconId == "dot" then return Icons.GAME_DOT_TEXTURE end
    local markerIndex = tonumber(tostring(iconId):match("^marker(%d)$"))
    if markerIndex and markerIndex >= 1 and markerIndex <= 8 then return Icons.RAID_MARKER_TEXTURE .. markerIndex end
    local jiberishName = tostring(iconId):match("^jiberish:(%l+%-%l+)$")
    if jiberishName and Icons.JiberishInstalled() then
        return Icons.JIBERISH_FOLDER .. jiberishName .. "-" .. Icons.JIBERISH_FILE_SIZE
    end
    -- A custom icon: a path, or a file id from the icon picker.
    if iconId == "custom" and ((type(customTexture) == "string" and customTexture:match("%S")) or type(customTexture) == "number") then
        return customTexture
    end
    return nil
end

-- The class icon styles on offer now, in order: { id, label }.
function Icons.ClassStyleList()
    local list = { { id = "game", label = "The game's class icons" } }
    if Icons.JiberishInstalled() then
        for _, style in ipairs(Icons.JIBERISH_CLASS_STYLES) do
            list[#list + 1] = { id = "jiberish:" .. style.file, label = "Jiberish: " .. style.name }
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
    if file and cell and Icons.JiberishInstalled() then
        local cells = Icons.JIBERISH_CLASS_GRID_CELLS
        return { texture = Icons.JIBERISH_CLASS_FOLDER .. file,
            texCoord = { cell[1] / cells, (cell[1] + 1) / cells, cell[2] / cells, (cell[2] + 1) / cells } }
    end
    local atlas = Icons.ClassAtlas(classFile)
    return atlas and { atlas = atlas } or nil
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
