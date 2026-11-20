-- A hint on the settings page: Gamepad Camera Offset, a separate addon, moves the
-- camera over your shoulder (keyboard or controller) and puts the crosshair on
-- your target. Shown only when it isn't installed; its button opens the copy box
-- (TextBox.lua) with its CurseForge page (the game can't open a web page). The
-- other addon is named here only as text: nothing calls it or depends on it.
local _, addon = ...

local RelatedAddon = {
    NAME = "GamepadCameraOffset",
    TITLE = "Gamepad Camera Offset",
    -- CurseForge's permanent short address for its project (redirects to its page).
    LINK = "https://www.curseforge.com/projects/1818297",
}
addon.RelatedAddon = RelatedAddon

function RelatedAddon.Installed()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, RelatedAddon.NAME)
    return succeeded and exists == true
end

function RelatedAddon.ShowLink()
    addon.TextBox.Copy(RelatedAddon.TITLE .. ": copy the link with Ctrl+C, install it, then restart the game.", RelatedAddon.LINK)
end

-- The settings page's button, when it isn't installed.
function RelatedAddon.AddButton(addButton)
    if RelatedAddon.Installed() then return end
    addButton(RelatedAddon.TITLE, "Get " .. RelatedAddon.TITLE, function() RelatedAddon.ShowLink() end,
        "To move the camera over your shoulder, with a controller too, and put this crosshair on your target. "
        .. "A separate addon; this one works without it.")
end
