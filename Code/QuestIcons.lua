-- Quest icons: left of the nameplates of units you still need for a quest, the
-- game's attack cursor (a sword) when you need to kill it, and its loot cursor (a
-- bag) when it drops an item you need; both when both.
--
-- What a unit is needed for is read from its tooltip (C_TooltipInfo.GetUnit, its
-- QuestObjective lines), each line's text matched with the unfinished objectives
-- in your quest log. In dungeons and raids, and in fights, the game can hide that
-- text from addons (a secret value: comparing it is an error), so it's never
-- compared then: a nameplate that shows up gets no icon, one already showing keeps
-- its icons, and every nameplate is read again when the fight ends.
--
-- Our icons are a frame of our own on each nameplate, made once (the game reuses
-- its nameplates); the game's nameplates are left as they are.
local _, addon = ...
local readable = addon.Readable   -- Target.lua

local QuestIcons = {
    KILL_ATLAS = "Crosshair_Attack_32",
    LOOT_ATLAS = "Crosshair_pickup_32",
    SIZE = 20,
    GAP = 3,         -- between the two icons
    PLATE_GAP = 6,   -- between the nameplate and the first icon
}
addon.QuestIcons = QuestIcons

-- A table addon code may read: not a secret value, nor a table the game forbids.
local function openTable(value)
    value = readable(value)
    if type(value) ~= "table" then return nil end
    if type(canaccesstable) == "function" and not canaccesstable(value) then return nil end
    return value
end

-- The unfinished objectives in your quest log, by their text: "monster" or "item".
-- Read again on first use after each QUEST_LOG_UPDATE.
local objectiveKinds
local function readObjectiveKinds()
    local kinds = {}
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                local text, kind = readable(objective.text), readable(objective.type)
                if type(text) == "string" and readable(objective.finished) == false
                    and (kind == "monster" or kind == "item") then
                    kinds[text] = kind
                end
            end
        end
    end
    return kinds
end

-- What a unit is needed for: kill, loot (true or false each), or nil when its
-- tooltip can't be read.
function QuestIcons.Needs(unit)
    local data = openTable(C_TooltipInfo.GetUnit(unit))
    local lines = data and openTable(data.lines)
    if not lines then return nil end
    objectiveKinds = objectiveKinds or readObjectiveKinds()
    local kill, loot = false, false
    for _, line in ipairs(lines) do
        line = openTable(line)
        local lineType = line and readable(line.type)
        if lineType == nil then return nil end
        if lineType == Enum.TooltipDataLineType.QuestObjective then
            local text = readable(line.leftText)
            if text == nil then return nil end
            local kind = objectiveKinds[text]
            if kind == "monster" then kill = true elseif kind == "item" then loot = true end
        end
    end
    return kill, loot
end

local iconsByPlate = {}   -- our frame on each nameplate that needed one: .kill, .loot

local function iconsOf(plate)
    local icons = iconsByPlate[plate]
    if icons then return icons end
    icons = CreateFrame("Frame", nil, plate)
    icons:SetAllPoints(plate)
    icons:SetFrameLevel(plate:GetFrameLevel() + 5)
    icons.kill = icons:CreateTexture(nil, "OVERLAY")
    icons.kill:SetAtlas(QuestIcons.KILL_ATLAS)
    icons.loot = icons:CreateTexture(nil, "OVERLAY")
    icons.loot:SetAtlas(QuestIcons.LOOT_ATLAS)
    for _, texture in ipairs({ icons.kill, icons.loot }) do texture:SetSize(QuestIcons.SIZE, QuestIcons.SIZE) end
    iconsByPlate[plate] = icons
    return icons
end

-- The sword nearest the nameplate, the bag beside it (or in its place).
local function showIcons(icons, kill, loot)
    local offset = QuestIcons.PLATE_GAP
    for _, icon in ipairs({ { texture = icons.kill, shown = kill }, { texture = icons.loot, shown = loot } }) do
        icon.texture:ClearAllPoints()
        if icon.shown then
            icon.texture:SetPoint("RIGHT", icons, "LEFT", -offset, 0)
            offset = offset + QuestIcons.SIZE + QuestIcons.GAP
        end
        icon.texture:SetShown(icon.shown)
    end
end

local function nameplateOf(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if type(plate) ~= "table" or plate:IsForbidden() then return nil end
    return plate
end

-- isNew: the nameplate just showed up for this unit, so icons it had were another's.
local function updateUnit(unit, isNew)
    local plate = nameplateOf(unit)
    if not plate then return end
    local kill, loot = false, false
    if addon.Settings().questIcons then
        kill, loot = QuestIcons.Needs(unit)
        if kill == nil then
            if not isNew then return end   -- unreadable: its icons stay
            kill, loot = false, false
        end
    end
    if kill or loot or iconsByPlate[plate] then showIcons(iconsOf(plate), kill, loot) end
end

local shownUnits = {}   -- the units with a nameplate now ("nameplate3")

-- Every nameplate again (the option, the quest log or a fight's end changed).
function QuestIcons.Refresh()
    for unit in pairs(shownUnits) do updateUnit(unit, false) end
end

local refreshPending = false
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        shownUnits[unit] = true
        updateUnit(unit, true)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        shownUnits[unit] = nil
    elseif event == "QUEST_LOG_UPDATE" then
        -- It comes in bursts: one refresh on the next frame.
        objectiveKinds = nil
        if refreshPending then return end
        refreshPending = true
        C_Timer.After(0, function()
            refreshPending = false
            QuestIcons.Refresh()
        end)
    else
        QuestIcons.Refresh()
    end
end)
