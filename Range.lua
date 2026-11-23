-- The sword, the paw, the shield and a beast's family icon on a target (Icons.lua) are gray while
-- none of your action bar spells can reach it, and in color once one can. Each action slot is
-- asked with the game's IsActionInRange (forever branch
-- Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua:624): true
-- in range, false out of range, nil when that slot can't tell (no spell, a
-- spell without range, one that can't target it). When no slot can tell, the
-- icon keeps its colors. Checked every CHECK_SECONDS while one is drawn.
local _, addon = ...

local Range = {
    CHECK_SECONDS = 0.25,
    ICONS = { swords = true, paw = true, shield = true, family = true },   -- the choices drawn gray out of reach
    LAST_SLOT = 180,   -- every action bar's slots, the bonus ones (forms, vehicles) too
}
addon.Range = Range

local function readable(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

-- true: a spell on your bars reaches the target; false: none does; nil: none can tell.
function Range.TargetInReach()
    if type(IsActionInRange) ~= "function" or type(HasAction) ~= "function" then return nil end
    local anyAnswer = false
    for slot = 1, Range.LAST_SLOT do
        if HasAction(slot) then
            local inRange = readable(IsActionInRange(slot, "target"))
            if inRange == true then return true end
            if inRange == false then anyAnswer = true end
        end
    end
    if anyAnswer then return false end
    return nil
end

-- Out of reach: the icon drawn gray.
function Range.IconGray(choice)
    return Range.ICONS[choice] == true and Range.TargetInReach() == false
end

-- While such an icon is drawn, it's drawn again when its reach changes.
local watcher = CreateFrame("Frame")
watcher:Hide()
Range.watcher = watcher
local untilCheck, lastGray = 0, nil
watcher:SetScript("OnUpdate", function(_, elapsed)
    untilCheck = untilCheck - elapsed
    if untilCheck > 0 then return end
    untilCheck = Range.CHECK_SECONDS
    local gray = Range.TargetInReach() == false
    if gray ~= lastGray then
        lastGray = gray
        addon.UpdateReticle()
    end
end)

-- Reticle.lua, after each draw.
function Range.Watch(choice, gray)
    lastGray = gray
    if Range.ICONS[choice] then watcher:Show() else watcher:Hide() end
end
