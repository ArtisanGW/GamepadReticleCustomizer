-- What's targeted now, read from the game: whether you have a target, a player
-- target's class, and how it stands to you. Only reads (UnitExists, UnitIsPlayer,
-- UnitClass, UnitReaction); the
-- target's nameplate isn't needed. A value the game hides from addons (a secret
-- value) counts as unknown.

local _, addon = ...

local function readable(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

-- The game's reaction (UnitReaction) as a word: 1 to 3 enemy, 4 neutral, 5 and up friendly.
local function reactionWord(reaction)
    reaction = tonumber(reaction)
    if not reaction then return nil end
    if reaction <= 3 then return "enemy" elseif reaction == 4 then return "neutral" end
    return "friendly"
end

-- { exists = true/false, isPlayer = true/false, classFile = "WARRIOR" or nil,
--   reaction = "enemy"/"neutral"/"friendly" or nil }
function addon.TargetInfo()
    local exists = type(UnitExists) == "function" and readable(UnitExists("target")) == true
    if not exists then return { exists = false, isPlayer = false } end
    local isPlayer = type(UnitIsPlayer) == "function" and readable(UnitIsPlayer("target")) == true
    local classFile
    if isPlayer and type(UnitClass) == "function" then
        local _, file = UnitClass("target")
        classFile = readable(file)
    end
    local reaction = type(UnitReaction) == "function" and reactionWord(readable(UnitReaction("target", "player"))) or nil
    return { exists = true, isPlayer = isPlayer, classFile = type(classFile) == "string" and classFile or nil,
        reaction = reaction }
end
