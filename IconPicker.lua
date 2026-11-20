-- Choosing the icon shown on a target the way the game's macro window chooses a
-- macro's icon: its own icon picker (IconSelectorPopupFrameTemplate, forever
-- branch Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:1714 and .lua:1807,
-- driven as Blizzard_MacroUI/Blizzard_MacroIconSelector.lua drives it), with its
-- grid, its spell/item filter and its controller support. The grid shows the
-- game's raid markers first, then every icon the macro picker offers
-- (IconDataProvider). Its text box takes a texture path instead of a name.
--   addon.IconPicker.Open(currentIcon, onChosen)   onChosen(icon): a file id or a path
local _, addon = ...

local IconPicker = {}
addon.IconPicker = IconPicker

-- Our icons first: the 8 raid markers.
local function ownIcons()
    local icons = {}
    for index = 1, 8 do icons[index] = addon.Icons.RAID_MARKER_TEXTURE .. index end
    return icons
end

-- The picker's icon list: ours, then the game's (the template asks it for these).
local function newIconList()
    local own = ownIcons()
    local gameIcons = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.None)
    local list = {}
    function list:GetNumIcons() return #own + gameIcons:GetNumIcons() end
    function list:GetIconByIndex(index)
        if index <= #own then return own[index] end
        return gameIcons:GetIconByIndex(index - #own)
    end
    function list:GetIndexOfIcon(icon)
        for index, ownIcon in ipairs(own) do
            if ownIcon == icon then return index end
        end
        local gameIndex = gameIcons:GetIndexOfIcon(icon)
        return gameIndex and gameIndex + #own or nil
    end
    function list:SetIconTypes(iconTypes) gameIcons:SetIconTypes(iconTypes) end
    function list:Release() gameIcons:Release() end
    return list
end

local picker

local function build()
    picker = CreateFrame("Frame", "GamepadCrosshairCustomizerIconPicker", UIParent, "IconSelectorPopupFrameTemplate")
    picker:ClearAllPoints()
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    picker:SetFrameStrata("DIALOG")
    picker.BorderBox.EditBoxHeaderText:SetText("Or a texture path (optional):")

    -- As the macro window's Update: the list, and the current icon selected.
    function picker:Update()
        local selectedIndex = self:GetIndexOfIcon(self.currentIcon) or 1
        self.BorderBox.IconSelectorEditBox:SetText(type(self.currentIcon) == "string" and not self:GetIndexOfIcon(self.currentIcon)
            and self.currentIcon or "")
        self.IconSelector:SetSelectedIndex(selectedIndex)
        self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(self.currentIcon or self:GetIconByIndex(selectedIndex))
        self.IconSelector:SetSelectionsDataProvider(GenerateClosure(self.GetIconByIndex, self), GenerateClosure(self.GetNumIcons, self))
        self.IconSelector:ScrollToSelectedIndex()
        self:SetSelectedIconText()
    end

    -- OK: the typed path if there's one, else the chosen icon.
    function picker:OkayButton_OnClick()
        IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self)
        local path = tostring(self.BorderBox.IconSelectorEditBox:GetText() or ""):match("^%s*(.-)%s*$")
        local icon = path ~= "" and path or self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
        if icon and self.onChosen then self.onChosen(icon) end
    end

    picker:HookScript("OnShow", function(self)
        self.iconDataProvider = self.iconDataProvider or newIconList()
        self:SetIconFilter(IconSelectorPopupFrameIconFilterTypes.All)
        self:Update()
        self.IconSelector:SetSelectedCallback(function(_, icon)
            self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(icon)
            self.BorderBox.IconSelectorEditBox:SetText("")
        end)
    end)
    IconPicker.frame = picker
end

function IconPicker.Open(currentIcon, onChosen)
    if InCombatLockdown() then
        print("|cff88ccffGamepad Crosshair Customizer|r the icon picker opens out of combat.")
        return
    end
    if not picker then build() end
    picker.currentIcon, picker.onChosen = currentIcon, onChosen
    if picker:IsShown() then picker:Update() else picker:Show() end
end
