-- A friendly NPC's job, and the game's icon for it, for the "By target" icon.
--
-- The job is the NPC's title, the line under its name in its tooltip ("Stable
-- Master", "Food & Drink"; without a title that line is its level, which has a
-- number or the word for level in it). Its icon comes from the game's own minimap
-- tracking list (C_Minimap.GetTrackingInfo: each NPC type's icon and its name in
-- the client's language), matched by name. Class trainers ("Warrior Trainer") get
-- that class's icon; other trainers, the profession trainers' tracking icon (found
-- by its type, C_Minimap.GetTrackingFilter, whatever the language).
local _, addon = ...

local NpcJobs = {
    PROFESSION_TRAINER_FILTER = "TrainerProfession",   -- Enum.MinimapTrackingFilter's name
}
addon.NpcJobs = NpcJobs

local function readable(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

-- The unit's title, or nil.
function NpcJobs.Title(unit)
    local tooltipInfo = _G.C_TooltipInfo
    if type(tooltipInfo) ~= "table" or type(tooltipInfo.GetUnit) ~= "function" then return nil end
    local succeeded, data = pcall(tooltipInfo.GetUnit, unit)
    local line = succeeded and type(data) == "table" and type(data.lines) == "table" and data.lines[2]
    local text = type(line) == "table" and readable(line.leftText)
    if type(text) ~= "string" or text == "" or text:find("%d") then return nil end
    if type(LEVEL) == "string" and text:find(LEVEL, 1, true) then return nil end
    return text
end

-- The game's tracking list: { name (lower case), texture, filterName }.
local function trackingTypes()
    local minimap = _G.C_Minimap
    if type(minimap) ~= "table" or type(minimap.GetNumTrackingTypes) ~= "function"
        or type(minimap.GetTrackingInfo) ~= "function" then return {} end
    local filterNames = {}
    if type(Enum) == "table" and type(Enum.MinimapTrackingFilter) == "table" then
        for filterName, value in pairs(Enum.MinimapTrackingFilter) do filterNames[value] = filterName end
    end
    local types = {}
    local succeeded, count = pcall(minimap.GetNumTrackingTypes)
    for index = 1, (succeeded and tonumber(count)) or 0 do
        local infoSucceeded, info = pcall(minimap.GetTrackingInfo, index)
        if infoSucceeded and type(info) == "table" and type(info.name) == "string" and info.texture then
            local filter = type(minimap.GetTrackingFilter) == "function" and select(2, pcall(minimap.GetTrackingFilter, index))
            local filterID = type(filter) == "table" and filter.filterID or nil
            types[#types + 1] = { name = info.name:lower(), texture = info.texture, filterName = filterNames[filterID] }
        end
    end
    return types
end

-- Whether a title and a tracking name are the same job: one holds the other,
-- also without a plural "s" ("Reagent Vendor" and "Reagents").
local function sameJob(title, trackingName)
    if title:find(trackingName, 1, true) or trackingName:find(title, 1, true) then return true end
    local singular = trackingName:gsub("s$", "")
    return #singular >= 4 and title:find(singular, 1, true) ~= nil
end

-- The class a title trains ("Warrior Trainer" -> "WARRIOR"), or nil.
local function trainedClass(title)
    for _, names in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(names) == "table" then
            for classFile, className in pairs(names) do
                if type(className) == "string" and title:find(className:lower(), 1, true) then return classFile end
            end
        end
    end
    return nil
end

local function isTrainer(title)
    local word = type(TRAINER) == "string" and TRAINER or "Trainer"
    return title:find(word:lower(), 1, true) ~= nil
end

-- The look for a unit's job: { atlas } / { texture, texCoord } (as Icons.ClassLook),
-- or nil when its job isn't known.
function NpcJobs.Look(unit, classStyle)
    local title = NpcJobs.Title(unit)
    if not title then return nil end
    title = title:lower()
    if isTrainer(title) then
        local classFile = trainedClass(title)
        if classFile then return addon.Icons.ClassLook(classFile, classStyle) end
    end
    local types = trackingTypes()
    for _, trackingType in ipairs(types) do
        if sameJob(title, trackingType.name) then return { texture = trackingType.texture } end
    end
    if isTrainer(title) then
        for _, trackingType in ipairs(types) do
            if trackingType.filterName == NpcJobs.PROFESSION_TRAINER_FILTER then return { texture = trackingType.texture } end
        end
    end
    return nil
end
