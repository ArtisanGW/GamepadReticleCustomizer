-- Debug only, not for release (.pkgmeta). Shows candidate icons side by side,
-- numbered, to pick one for a kind of target (TITLE). Atlases this client lacks
-- are left out; the numbered list goes to GamepadReticleCustomizerDebugDB.iconPicks.
-- A few seconds after login, for SHOW_SECONDS, with a timer.
local IconPicks = {
    TITLE = "Neutral NPC icon",
    START_DELAY = 3,
    SHOW_SECONDS = 60,
    ICON_SIZE = 48,
    -- color: a tint as the reticle could draw it (yellow: neutral's own color)
    CANDIDATES = {
        { file = "Interface\\Cursor\\Attack", color = { 1, 0.82, 0 } },
        { file = "Interface\\Cursor\\UnableAttack", color = { 1, 0.82, 0 } },
        { atlas = "hunter-beastmastery" },
        { atlas = "nameplates-icon-flag-neutral" },
        { atlas = "honorsystem-portrait-neutral" },
        { atlas = "FactionNeutral" },
        { atlas = "Ping_Marker_Icon_Warning" },
        { atlas = "Ping_Marker_Icon_NonThreat" },
        { atlas = "WildBattlePet", color = { 1, 0.82, 0 } },
        { file = "Interface\\Icons\\INV_Misc_MonsterClaw_04", color = { 1, 0.82, 0 } },
        { file = "Interface\\Icons\\Ability_Hunter_Pet_Cat" },
        { file = "Interface\\Icons\\INV_Misc_Bone_01" },
    },
}

local function debugStore()
    if type(GamepadReticleCustomizerDebugDB) ~= "table" then GamepadReticleCustomizerDebugDB = {} end
    return GamepadReticleCustomizerDebugDB
end

local function atlasExists(atlas)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function show()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -140)
    panel:SetFrameStrata("DIALOG")
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.8)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -10)

    local log, shown = {}, 0
    for _, candidate in ipairs(IconPicks.CANDIDATES) do
        local name = candidate.atlas or candidate.file
        if candidate.file or atlasExists(candidate.atlas) then
            shown = shown + 1
            local icon = panel:CreateTexture(nil, "ARTWORK")
            icon:SetSize(IconPicks.ICON_SIZE, IconPicks.ICON_SIZE)
            icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (shown - 1) * (IconPicks.ICON_SIZE + 24), -44)
            if candidate.atlas then icon:SetAtlas(candidate.atlas) else icon:SetTexture(candidate.file) end
            if candidate.color then icon:SetVertexColor(candidate.color[1], candidate.color[2], candidate.color[3]) end
            local number = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            number:SetPoint("TOP", icon, "BOTTOM", 0, -4)
            number:SetText(shown)
            log[#log + 1] = shown .. " = " .. name .. (candidate.color and " (yellow)" or "")
        else
            log[#log + 1] = name .. " (missing)"
        end
    end
    debugStore().iconPicks2 = log
    panel:SetSize(math.max(360, 16 + shown * (IconPicks.ICON_SIZE + 24)), IconPicks.ICON_SIZE + 90)

    local endTime = GetTime() + IconPicks.SHOW_SECONDS
    local ticker
    ticker = C_Timer.NewTicker(0.5, function()
        local left = endTime - GetTime()
        if left <= 0 then ticker:Cancel(); panel:Hide(); return end
        title:SetText(string.format("%s: which number? (%d s)", IconPicks.TITLE, math.ceil(left)))
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() C_Timer.After(IconPicks.START_DELAY, show) end)
