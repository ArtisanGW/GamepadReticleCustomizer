-- Object icons: the game's interact icons on more of what's around you (ore,
-- herbs, skinning, chests, mailboxes, chairs), from farther away and in a wider
-- arc. Four of the game's own settings (CVars), set while the option is on:
--   SoftTargetInteract              3: the interact key on a controller and on a keyboard (game: 1, controller only)
--   SoftTargetInteractArc           2: a wider arc (game: 0; the controller UI's: 1)
--   SoftTargetIconGameObject        1: icons on objects too, not only on NPCs
--   nameplateGameObjectMaxDistance  60 yards (game: 30)
-- Your own values are kept first (settings.objectIconsBefore, saved) and put back
-- when the option is turned off and at each logout, so without the addon the
-- game has yours; each login sets ours again. A value you change yourself while
-- it's on stays yours. The game refuses SoftTargetInteract and
-- nameplateGameObjectMaxDistance (secure CVars) from addons in a fight: a change
-- then waits for its end.
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

-- "60" and "60.000000" are the same value.
local function sameValue(first, second)
    return first == second or (tonumber(first) ~= nil and tonumber(first) == tonumber(second))
end

-- Your values back, for those still at ours.
local function putBack(settings)
    local before = settings.objectIconsBefore
    if type(before) ~= "table" then return end
    for name, value in pairs(ObjectIcons.VALUES) do
        local yours = before[name]
        if yours ~= nil and not sameValue(yours, value) and sameValue(C_CVar.GetCVar(name), value) then
            C_CVar.SetCVar(name, yours)
        end
    end
end

-- Ours while the option is on, else yours back. In a fight: at its end.
function ObjectIcons.Apply()
    if InCombatLockdown() then
        ObjectIcons.waitingForFightEnd = true
        return
    end
    ObjectIcons.waitingForFightEnd = nil
    local settings = addon.Settings()
    if not settings.objectIcons then
        putBack(settings)
        settings.objectIconsBefore = nil
        return
    end
    if type(settings.objectIconsBefore) ~= "table" then
        local before = {}
        for name in pairs(ObjectIcons.VALUES) do before[name] = C_CVar.GetCVar(name) end
        settings.objectIconsBefore = before
    end
    for name, value in pairs(ObjectIcons.VALUES) do
        if not sameValue(C_CVar.GetCVar(name), value) then C_CVar.SetCVar(name, value) end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        -- Yours back, still kept for the next login (a reload counts too).
        if not InCombatLockdown() then putBack(addon.Settings()) end
    elseif event == "PLAYER_ENTERING_WORLD" or ObjectIcons.waitingForFightEnd then
        ObjectIcons.Apply()
    end
end)
