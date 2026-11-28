-- Object icons: the game's interact icons on more of what's around you (ore,
-- herbs, skinning, chests, mailboxes, chairs), from farther away and in a wider
-- arc. Four of the game's own settings (CVars), while the option is on:
--   SoftTargetInteract              3: the interact key on a controller and on a keyboard (game: 1, controller only)
--   SoftTargetInteractArc           2: a wider arc (game: 0; the controller UI's: 1)
--   SoftTargetIconGameObject        1: icons on objects too, not only on NPCs (the controller UI's already)
--   nameplateGameObjectMaxDistance  60 yards (game: 30)
--
-- Set as temporary values (C_CVar.SetTempCVar), as the controller UI sets its own
-- for three of them (Blizzard_Gamepad/Core.lua, forever branch): measured in the
-- game, SetCVar doesn't change a value the controller UI holds that way. A
-- temporary value is never saved, so your own settings stay as they are, and
-- nothing is left behind without the addon; each loading screen sets ours again
-- (the game sets or clears its own on each UI load). Turned off, what was there
-- before comes back: the controller UI's temporary value if it had one, else
-- yours. The game refuses SoftTargetInteract and nameplateGameObjectMaxDistance
-- (secure CVars) from addons in a fight: a change then waits for its end.
local _, addon = ...

local ObjectIcons = {
    VALUES = {
        SoftTargetInteract = "3",
        SoftTargetInteractArc = "2",
        SoftTargetIconGameObject = "1",
        nameplateGameObjectMaxDistance = "60",
    },
}
addon.ObjectIcons = ObjectIcons

-- What each CVar we set held before: the temporary value there was, or false for none.
local before = {}

-- "60" and "60.000000" are the same value.
local function sameValue(first, second)
    return first == second or (tonumber(first) ~= nil and tonumber(first) == tonumber(second))
end

local function setOurs()
    for name, value in pairs(ObjectIcons.VALUES) do
        local current = C_CVar.GetCVar(name)
        if not sameValue(current, value) then
            if before[name] == nil then
                -- Without a temporary value, the saved one shows: the same, there was none.
                C_CVar.RemoveTempCVar(name)
                before[name] = not sameValue(C_CVar.GetCVar(name), current) and current
            end
            C_CVar.SetTempCVar(name, value)
        end
    end
end

-- What was there before, for those still at ours.
local function putBack()
    for name, temporaryValue in pairs(before) do
        if sameValue(C_CVar.GetCVar(name), ObjectIcons.VALUES[name]) then
            if temporaryValue then C_CVar.SetTempCVar(name, temporaryValue) else C_CVar.RemoveTempCVar(name) end
        end
    end
    before = {}
end

-- Ours while the option is on, else what was there before. In a fight: at its end.
function ObjectIcons.Apply()
    if InCombatLockdown() then
        ObjectIcons.waitingForFightEnd = true
        return
    end
    ObjectIcons.waitingForFightEnd = nil
    if addon.Settings().objectIcons then setOurs() else putBack() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or ObjectIcons.waitingForFightEnd then ObjectIcons.Apply() end
end)
