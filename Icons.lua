-- The shapes the crosshair can take, each an icon id:
--   "dot"             the game's own dot (its texture, GamepadReticle.xml:94)
--   "marker1".."8"    the game's raid target markers: star, circle, diamond,
--                     triangle, moon, square, cross, skull
--   "jiberish:<name>" JiberishUI Fabled Icons' crosshair shapes, offered only
--                     when that addon is installed (enabled or not: the game reads
--                     the files from its folder either way). Named here only as
--                     text: nothing calls it or depends on it, nothing is copied,
--                     and its shapes are credited (its license asks for that).
--   "custom"          any texture path you type (the customTexture setting)
local _, addon = ...

local Icons = {
    GAME_DOT_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_",
    RAID_MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" },
    JIBERISH_ADDON = "JiberishIcons",
    JIBERISH_FOLDER = "Interface\\AddOns\\JiberishIcons\\Media\\Crosshair\\",
    JIBERISH_SHAPES = { "circle", "diamond", "plus", "splitplus", "splitx", "square", "triangle", "x" },
    JIBERISH_WEIGHTS = { "bold", "thin" },
    JIBERISH_FILE_SIZE = 128,   -- each shape comes in 32, 64, 128 and 256 px
    JIBERISH_CREDIT = "Shapes from JiberishUI Fabled Icons",
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

local function raidMarkerName(index)
    return _G["RAID_TARGET_" .. index] or Icons.RAID_MARKER_NAMES[index]
end

local function capitalized(text) return (text:gsub("^%l", string.upper)) end

-- Every icon on offer now, in order: { id, label }.
function Icons.List()
    local list = { { id = "dot", label = "The game's dot" } }
    for index = 1, 8 do
        list[#list + 1] = { id = "marker" .. index, label = "Raid marker: " .. raidMarkerName(index) }
    end
    if Icons.JiberishInstalled() then
        for _, shape in ipairs(Icons.JIBERISH_SHAPES) do
            for _, weight in ipairs(Icons.JIBERISH_WEIGHTS) do
                list[#list + 1] = { id = "jiberish:" .. shape .. "-" .. weight,
                    label = "Jiberish: " .. capitalized(shape) .. ", " .. weight }
            end
        end
    end
    list[#list + 1] = { id = "custom", label = "Your own texture (Custom texture... button)" }
    return list
end

-- The texture path an icon id draws, or nil if there's none (an unknown id, a
-- Jiberish shape without the addon, or "custom" with no path yet).
function Icons.Texture(iconId, customTexture)
    if iconId == "dot" then return Icons.GAME_DOT_TEXTURE end
    local markerIndex = tonumber(tostring(iconId):match("^marker(%d)$"))
    if markerIndex and markerIndex >= 1 and markerIndex <= 8 then return Icons.RAID_MARKER_TEXTURE .. markerIndex end
    local jiberishName = tostring(iconId):match("^jiberish:(%l+%-%l+)$")
    if jiberishName and Icons.JiberishInstalled() then
        return Icons.JIBERISH_FOLDER .. jiberishName .. "-" .. Icons.JIBERISH_FILE_SIZE
    end
    if iconId == "custom" and type(customTexture) == "string" and customTexture:match("%S") then
        return customTexture
    end
    return nil
end
