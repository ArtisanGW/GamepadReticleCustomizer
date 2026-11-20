-- A hint on the settings page: Gamepad Reticle On Target, a separate addon, puts
-- the reticle under your target's nameplate, which the icon on a target needs
-- (the game keeps the reticle in the middle of the screen). Shown only when it
-- isn't installed; its button opens the copy box (Popup.lua) with its page (the
-- game can't open a web page). The other addon is named here only as text:
-- nothing calls it or depends on it.
local _, addon = ...

local RelatedAddon = {
    NAME = "GamepadReticleOnTarget",
    TITLE = "Gamepad Reticle On Target",
    -- CurseForge's permanent short address for its project (redirects to its page).
    LINK = "https://www.curseforge.com/projects/1819101",
}
addon.RelatedAddon = RelatedAddon

function RelatedAddon.Installed()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, RelatedAddon.NAME)
    return succeeded and exists == true
end

function RelatedAddon.ShowLink()
    addon.Popup.Show({
        text = "To get " .. RelatedAddon.TITLE .. ":\n"
            .. "• Copy the link (Ctrl+C)\n"
            .. "• Install it\n"
            .. "• Reload",
        copyText = RelatedAddon.LINK,
        buttons = { { text = "Reload", reload = true }, { text = "Close" } },
    })
end

-- The settings page's button, when it isn't installed.
function RelatedAddon.AddButton(addButton)
    if RelatedAddon.Installed() then return end
    addButton(RelatedAddon.TITLE, "Get " .. RelatedAddon.TITLE, function() RelatedAddon.ShowLink() end,
        "Puts the reticle just below your target's nameplate, so the icon on a target shows there.\n\n"
        .. "A separate addon; this one works without it.")
end
