-- GamepadReticleCustomizer against a fake game: the controller's reticle, frames
-- and textures, the Settings API, the color picker, a controller, addons installed
-- or not. From GamepadReticleCustomizer:  luajit tests/run.lua
local reportLine = print   -- the tests replace print to read what the addon says
local failed, passed = 0, 0
local only = os.getenv("GRC_TEST")   -- run only the tests whose name holds this
local function test(name, fn)
    if only and not name:find(only, 1, true) then return end
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; reportLine("FAIL " .. name .. "\n" .. err) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function near(a, b, msg) if math.abs(a - b) > 0.01 then error((msg or "") .. ": expected " .. b .. ", got " .. a, 2) end end
local function readFile(path) local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text end

-- The files the .toc loads, in its order; releaseBuild: as the packager makes it
-- (its do-not-package block deleted).
local function tocFiles(releaseBuild)
    local toc = readFile("GamepadReticleCustomizer.toc"):gsub("\r", "")
    if releaseBuild then toc = toc:gsub("#@do%-not%-package@.-#@end%-do%-not%-package@\n?", "") end
    local files = {}
    for line in toc:gmatch("[^\n]+") do
        if not line:find("^#") then files[#files + 1] = line end
    end
    return files
end

-- Fake regions: frames, textures, font strings and edit boxes, with what the addon uses.
local game
local function newRegion(parent)
    local region = { parent = parent, shown = true, alpha = 1, width = 0, height = 0, color = { 1, 1, 1, 1 } }
    function region:SetPoint(_, relativeTo) self.relativeTo = relativeTo end
    -- As the game: anchored to a restricted region (a nameplate), it can't be measured.
    function region:GetPoint()
        if type(self.relativeTo) == "table" and self.relativeTo.restricted then
            error("GetPoint(): Action[FrameMeasurement] failed because[Can't measure restricted regions]")
        end
        if self.relativeTo then return "CENTER", self.relativeTo, "CENTER", 0, 0 end
    end
    function region:SetAllPoints() end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:GetWidth() return self.width end
    function region:GetHeight() return self.height end
    function region:Show() self.shown = true end
    function region:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function region:GetName() return self.name end
    function region:SetShown(shown) self.shown = shown and true or false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:GetAlpha() return self.alpha end
    function region:SetTexture(path) self.texture, self.atlas = path, nil; return true end
    function region:SetAtlas(atlas) self.atlas, self.texture = atlas, nil end
    function region:GetAtlas() return self.atlas end
    function region:SetTexCoord(...) self.texCoord = { ... } end
    -- As the game: the four corners, upper left, lower left, upper right, lower right.
    function region:GetTexCoord()
        local c = self.texCoord or { 0, 1, 0, 1 }   -- left, right, top, bottom as set
        return c[1], c[3], c[1], c[4], c[2], c[3], c[2], c[4]
    end
    function region:GetTexture() return self.texture end
    function region:SetColorTexture(red, green, blue, alpha) self.color = { red, green, blue, alpha } end
    function region:SetVertexColor(red, green, blue, alpha) self.color = { red, green, blue, alpha or 1 } end
    function region:GetVertexColor() return unpack(self.color) end
    function region:GetEffectiveScale() return 1 end
    function region:GetCenter() return 640, 400 end
    function region:SetFrameStrata(strata) self.strata = strata end
    function region:GetFrameStrata() return self.strata or "MEDIUM" end
    function region:SetClampedToScreen() end
    function region:SetToplevel() end
    function region:SetJustifyH(justify) self.justify = justify end
    function region:GetStringHeight() return 30 end
    function region:ClearAllPoints() end
    function region:SetFrameLevel(level) self.level = level end
    function region:GetFrameLevel() return self.level or 1 end
    function region:EnableMouse() end
    function region:SetText(text) self.text = text end
    function region:GetText() return self.text end
    function region:SetWidth(width) self.width = width end
    function region:SetHeight(height) self.height = height end
    function region:SetAutoFocus() end
    function region:SetFocus() self.focused = true end
    function region:HighlightText() self.highlighted = true end
    function region:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
    function region:RegisterForClicks() end
    function region:CreateTexture() return newRegion(self) end
    function region:CreateFontString() return newRegion(self) end
    function region:Click() if self.scripts and self.scripts.OnClick then self.scripts.OnClick(self) end end
    return region
end

local function boot(options)
    options = options or {}
    game = { frames = {}, settings = {}, callbacks = {}, controls = {}, time = 100, printed = {}, timers = {} }
    -- Something putting the reticle under the target's nameplate as the target or
    -- the plates change (the game lets any addon move it), unless
    -- options.reticleOnTarget == false: then it stays where the game puts it.
    local reticleEvents = { PLAYER_TARGET_CHANGED = true, NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true }
    local function fire(event, ...)
        for _, frame in ipairs(game.frames) do if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end end
        local unit = ...
        local targetsPlate = event == "PLAYER_TARGET_CHANGED" or (game.target and unit == game.target.plateUnit)
        if reticleEvents[event] and targetsPlate and options.reticleOnTarget ~= false and _G.GamepadReticle then
            local onPlate = C_NamePlate.GetNamePlateForUnit("target") ~= nil
            GamepadReticle:ClearAllPoints()
            GamepadReticle:SetPoint("CENTER", onPlate and { restricted = true } or UIParent, "BOTTOM")
        end
    end
    game.fire = fire
    _G.InputUtil = { IsGamepadUIEnabled = function() return options.keyboard ~= true end }
    _G.GetTime = function() return game.time end
    _G.hooksecurefunc = function(object, method, hook)
        local original = object[method]
        object[method] = function(...) local result = original(...); hook(...); return result end
    end
    _G.C_Timer = { After = function(_, fn) game.timers[#game.timers + 1] = fn end }
    _G.InCombatLockdown = function() return game.combat == true end
    _G.UIParent = newRegion(nil)
    function UIParent:GetHeight() return 768 end
    _G.GetPhysicalScreenSize = function() return 2560, 1440 end
    _G.GetBuildInfo = function() return "1.60.1", "70959", "", 16001 end
    -- The target: game.target = { isPlayer, classFile, reaction (UnitReaction's number) } or nil.
    local function targetField(unit, field) if unit == "target" and game.target then return game.target[field] end end
    _G.UnitExists = function(unit) return unit == "target" and game.target ~= nil end
    _G.UnitIsPlayer = function(unit) return targetField(unit, "isPlayer") == true end
    _G.UnitClass = function(unit)
        local classFile = unit == "player" and "SHAMAN" or targetField(unit, "classFile")
        return classFile and classFile:lower(), classFile
    end
    _G.UnitReaction = function(unit) return targetField(unit, "reaction") end
    _G.UnitIsUnit = function(unit, other) return other == "target" and game.target ~= nil and unit == game.target.plateUnit end
    -- The game's class atlases: each a cell of one file (as GetAtlasInfo reports them).
    -- The game's other atlases "By target" uses (none, with options.noByTargetAtlases).
    local byTargetAtlases = { ["UI-HUD-UnitFrame-Player-PVP-AllianceIcon"] = true, ["UI-HUD-UnitFrame-Player-PVP-HordeIcon"] = true,
        ["Crosshair_PVP_128"] = true, ["QuestTurnin"] = true, ["Crosshair_Speak_128"] = true }
    _G.C_Texture = { GetAtlasInfo = function(atlas)
        if atlas:find("^classicon%-") and options.classAtlases ~= false then
            return { file = "classicons-file", leftTexCoord = 0.5, rightTexCoord = 0.75, topTexCoord = 0.25, bottomTexCoord = 0.5 }
        end
        if byTargetAtlases[atlas] and not options.noByTargetAtlases then
            return { file = atlas .. "-file", leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
        end
    end }
    -- The target's side, owner and tooltip title (game.target.faction, .controlled, .title).
    _G.UnitFactionGroup = function(unit)
        if unit == "player" then return "Horde" end
        return game.target and unit == "target" and game.target.faction or nil
    end
    _G.UnitPlayerControlled = function(unit) return game.target ~= nil and unit == "target" and (game.target.controlled or game.target.isPlayer) == true end
    _G.C_TooltipInfo = { GetUnit = function(unit)
        if not (game.target and unit == "target") then return nil end
        return { lines = { { leftText = "Someone" }, { leftText = game.target.title or "Level 30" } } }
    end }
    _G.LEVEL, _G.TRAINER = "Level", "Trainer"
    _G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage", PRIEST = "Priest" }
    -- The game's minimap tracking list: names in the client's language, icons, types.
    _G.Enum = _G.Enum or {}
    Enum.MinimapTrackingFilter = { StableMaster = 4096, TrainerProfession = 256, VenderFood = 32, Innkeeper = 64 }
    local tracking = {
        { name = "Stable Master", texture = 136466, filterID = 4096 },
        { name = "Food & Drink", texture = 136459, filterID = 32 },
        { name = "Innkeeper", texture = 136458, filterID = 64 },
        { name = "Profession Trainers", texture = 136463, filterID = 256 },
    }
    _G.C_Minimap = {
        GetNumTrackingTypes = function() return #tracking end,
        GetTrackingInfo = function(index) local entry = tracking[index]; return { name = entry.name, texture = entry.texture, active = false, type = "other", subType = 0 } end,
        GetTrackingFilter = function(index) return { filterID = tracking[index].filterID } end,
    }
    game.classColors = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
        PRIEST = { r = 1, g = 1, b = 1 }, DRUID = { r = 1, g = 0.49, b = 0.04 } }
    _G.C_ClassColor = { GetClassColor = function(classFile) return game.classColors[classFile] end }
    -- The target's nameplate (unless target.nameplate == false: a vendor, a minion, or
    -- off screen), a player's health bar in its class's color (as the game shows them).
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        if unit ~= "target" or not game.target or game.target.nameplate == false or options.noNameplates then return nil end
        local color = game.classColors[game.target.classFile] or { r = 0, g = 1, b = 0 }
        return { UnitFrame = { healthBar = { GetStatusBarColor = function() return color.r, color.g, color.b end } } }
    end }
    _G.date = os.date
    -- The game's file ids by path (GetFileIDFromPath): every file but one called "missing".
    _G.GetFileIDFromPath = function(path) if not tostring(path):find("missing", 1, true) then return 100000 + #path end end
    _G.NineSliceUtil = { ApplyLayoutByName = function(container, layoutName) container.layoutName = layoutName end }
    _G.CreateFrame = function(_, name, parent, template)
        local frame = newRegion(parent)
        frame.template, frame.name = template, name
        frame.events, frame.scripts = {}, {}
        if name then _G[name] = frame end
        function frame:RegisterEvent(eventName) self.events[eventName] = true end
        function frame:UnregisterEvent(eventName) self.events[eventName] = nil end
        function frame:SetScript(scriptType, handler) self.scripts[scriptType] = handler end
        game.frames[#game.frames + 1] = frame
        return frame
    end
    -- options.jiberish: installed; options.jiberishOff: installed but turned off for this character.
    _G.C_AddOns = {
        DoesAddOnExist = function(name)
            return (name == "JiberishIcons" and (options.jiberish == true or options.jiberishOff == true))
                or (name == "GamepadReticleOnTarget" and (options.reticleOnTargetInstalled == true or options.reticleOnTargetOff == true))
        end,
        -- As the game: GetAddOnInfo's loadable and reason; the switch reports "some
        -- characters" (1) for all, as when other characters still have it on.
        GetAddOnInfo = function(name)
            if name == "JiberishIcons" and options.jiberishOff then return name, name, "", false, "DISABLED", "INSECURE" end
            return name, name, "", true, "", "INSECURE"
        end,
        -- As the game: the character key is the player's GUID; a name isn't one (it reads "on").
        GetAddOnEnableState = function(name, character)
            if name == "JiberishIcons" and options.jiberishOff then
                if character == "Player-93-0A1B2C3D" or character == nil then return 0 end
                return 2
            end
            if name == "GamepadReticleOnTarget" and options.reticleOnTargetOff and character == "Player-93-0A1B2C3D" then return 0 end
            return 2
        end,
        EnableAddOn = function(name, character) game.enabledAddOn = { name = name, character = character, saved = false } end,
        SaveAddOns = function() if game.enabledAddOn then game.enabledAddOn.saved = true end end,
    }
    _G.UnitName = function(unit) if unit == "player" then return "Artio" end end
    _G.UnitGUID = function(unit) if unit == "player" then return "Player-93-0A1B2C3D" end end
    _G.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
    local function addControl(kind, setting, extra)
        game.controls[#game.controls + 1] = { kind = kind, setting = setting, extra = extra }
    end
    local layout = { AddInitializer = function(_, initializer) addControl("button", nil, initializer) end }
    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },
        RegisterVerticalLayoutCategory = function(name) return { name = name, GetID = function() return 42 end }, layout end,
        RegisterAddOnSetting = function(_, variable, key, tbl, _, label, default)
            if tbl[key] == nil then tbl[key] = default end
            local setting = { variable = variable, key = key, tbl = tbl, label = label }
            function setting:SetValue(value)
                self.tbl[self.key] = value
                if game.callbacks[self.variable] then game.callbacks[self.variable](nil, self, value) end
            end
            function setting:GetValue() return self.tbl[self.key] end
            game.settings[variable] = setting
            return setting
        end,
        SetOnValueChangedCallback = function(variable, fn) game.callbacks[variable] = fn end,
        RegisterProxySetting = function(_, variable, _, label, _, getValue, setValue)
            local setting = { variable = variable, label = label, getValue = getValue, setValue = setValue }
            game.settings[variable] = setting
            return setting
        end,
        CreateCheckbox = function(_, setting, tooltip) addControl("checkbox", setting, { tooltip = tooltip }) end,
        CreateSlider = function(_, setting, sliderOptions, tooltip) sliderOptions.tooltip = tooltip; addControl("slider", setting, sliderOptions) end,
        CreateSliderOptions = function(minimum, maximum, step)
            return { minimum = minimum, maximum = maximum, step = step, SetLabelFormatter = function(self, _, fn) self.format = fn end }
        end,
        CreateControlTextContainer = function()
            local container = { data = {} }
            function container:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
            function container:GetData() return self.data end
            return container
        end,
        CreateColorSwatch = function(_, setting, tooltip) addControl("swatch", setting, { tooltip = tooltip }) end,
        RegisterAddOnCategory = function(category) game.category = category end,
        OpenToCategory = function(id) game.opened = id end,
    }
    _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip, addSearchTags)
        assert(addSearchTags ~= nil, "the game asserts addSearchTags isn't nil")
        return { name = name, buttonText = buttonText, onClick = onClick, tooltip = tooltip }
    end
    _G.SlashCmdList = {}
    -- The game's settings window: shown or not, and the page it shows (game.currentCategory).
    _G.SettingsPanel = newRegion(nil)
    SettingsPanel.shown = false
    function SettingsPanel:GetCurrentCategory() return game.currentCategory end
    SettingsPanel.strata = "HIGH"
    -- The active controller's button icons (atlases), unless options.noControllerIcons.
    _G.InputIconTextureSetUtility = not options.noControllerIcons and
        { GetNormalActiveInputIconButtonTexture = function(key) return "gamepad-test-" .. key:lower() end } or nil
    game.bindings, game.bindingOwners = {}, {}
    _G.SetOverrideBindingClick = function(owner, _, key, buttonName) game.bindings[key] = buttonName; game.bindingOwners[key] = owner end
    _G.ClearOverrideBindings = function(owner)
        for key, keyOwner in pairs(game.bindingOwners) do
            if keyOwner == owner then game.bindings[key], game.bindingOwners[key] = nil, nil end
        end
    end
    -- The controller UI's reticle: Blizzard's dot, white, never tinted by the game.
    local icons = newRegion(nil)
    icons.StandardIcon = newRegion(icons)
    icons.StandardIcon.texture = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    icons.StandardIcon.alpha = options.gameDotAlpha or 1
    _G.GamepadReticle = newRegion(nil)
    GamepadReticle.Icons = icons
    -- The game's color picker: shown or not, its hooks, and its ColorSelect's HSV.
    game.picker = { hooks = {}, hsv = { 120, 1, 0.5 } }
    _G.ColorPickerFrame = {
        IsShown = function() return game.picker.shown == true end,
        HookScript = function(_, script, fn) game.picker.hooks[script] = fn end,
        Show = function() game.picker.shown = true; if game.picker.hooks.OnShow then game.picker.hooks.OnShow() end end,
        Hide = function() game.picker.shown = false; if game.picker.hooks.OnHide then game.picker.hooks.OnHide() end end,
        Content = {
            ColorPicker = {
                GetColorHSV = function() return game.picker.hsv[1], game.picker.hsv[2], game.picker.hsv[3] end,
                SetColorHSV = function(_, h, s, v) game.picker.hsv = { h, s, v } end,
                GetColorAlpha = function() return game.picker.alpha end,
                SetColorAlpha = function(_, a) game.picker.alpha = a end,
                SetWidth = function() end,
                Alpha = { Show = function() game.picker.barShown = true end },
                AlphaThumb = { Show = function() end },
            },
            AlphaBackground = { Show = function() end },
        },
        SetWidth = function() end,
    }
    game.cameraStickY, game.moveStickX, game.moveStickY = 0, 0, 0
    game.padUp, game.padDown = false, false
    _G.C_GamePad = {
        GetDeviceMappedState = function()
            return { stickCount = 2, sticks = { { x = game.moveStickX, y = game.moveStickY }, { x = 0, y = game.cameraStickY } },
                buttonCount = 3, buttons = { false, game.padUp, game.padDown } }
        end,
        ButtonIndexToConfigName = function(index) return ({ [0] = "PAD1", [1] = "PADDUP", [2] = "PADDDOWN" })[index] end,
        StickIndexToConfigName = function(index) return index == 0 and "Movement" or "Camera" end,
    }
    _G.GamepadReticleCustomizerDB = options.saved
    _G.GamepadReticleCustomizerDebugDB = options.debugSaved
    _G.GamepadReticleCustomizerPopup = nil
    _G.print = function(t) game.printed[#game.printed + 1] = t end
    local namespace = {}
    for _, fileName in ipairs(tocFiles(options.releaseBuild)) do assert(loadfile(fileName))("GamepadReticleCustomizer", namespace) end
    fire("ADDON_LOADED", "GamepadReticleCustomizer")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD")
end
-- Changes the target as the game does: then PLAYER_TARGET_CHANGED.
local function setTarget(target) game.target = target; game.fire("PLAYER_TARGET_CHANGED") end
local function frame() local timers = game.timers; game.timers = {}; for _, fn in ipairs(timers) do fn() end end
local function runUntilNoTimersLeft()
    for _ = 1, 5000 do if #game.timers == 0 then return end; frame() end
    error("the timers never ended")
end

local function layer() return GamepadReticleCustomizer.Reticle.Layer() end
local function colorOf(region)
    return string.format("%.2f %.2f %.2f %.2f", region.color[1], region.color[2], region.color[3], region.color[4])
end
local function setting(key) return game.settings["GamepadReticleCustomizer_" .. key] end
-- A control by its label, or a button by its row's name or its button text.
local function control(kind, labelOrName)
    for _, entry in ipairs(game.controls) do
        local label = entry.setting and entry.setting.label or (entry.extra and entry.extra.name)
        local buttonText = entry.extra and entry.extra.buttonText
        if entry.kind == kind and (label == labelOrName or buttonText == labelOrName) then return entry end
    end
end
local function controlList()
    local labels = {}
    for _, entry in ipairs(game.controls) do
        local label = entry.setting and entry.setting.label or entry.extra.name
        if label:match("^%s*$") then label = "(" .. entry.extra.buttonText .. ")" end   -- a button with no row label
        labels[#labels + 1] = entry.kind .. ":" .. label
    end
    return table.concat(labels, ", ")
end
-- The popup: shown, its text, its line to copy, and its buttons' texts in order.
local function popup() return GamepadReticleCustomizer.Popup.frame end
local function popupButtons()
    local frame, texts = popup(), {}
    local buttons = { frame.reloadButton }
    for _, button in ipairs(frame.buttons) do buttons[#buttons + 1] = button end
    for _, button in ipairs(buttons) do
        if button:IsShown() then texts[#texts + 1] = (button.attributes and "[secure] " or "") .. button.text end
    end
    table.sort(texts)
    return table.concat(texts, ", ")
end
local function clickPopupButton(text)
    local frame = popup()
    for _, button in ipairs(frame.buttons) do if button:IsShown() and button.text == text then return button:Click() end end
    if frame.reloadButton:IsShown() and frame.reloadButton.text == text then
        -- A secure /reload button: its PreClick runs, then the game reloads (here: noted).
        frame.reloadButton.scripts.PreClick(frame.reloadButton)
        game.reloaded = frame.reloadButton.attributes.macrotext
    end
end

-- A choice slider's labels, one per step (what the controller steps through).
local function choiceLabels(label)
    local options, labels = control("slider", label).extra, {}
    for value = options.minimum, options.maximum do labels[#labels + 1] = options.format(value) end
    return labels
end
-- Picks a shape as the slider does: by its step.
local function choose(key, id)
    local icons = GamepadReticleCustomizer.Icons
    local lists = { icon = icons.ReticleList, targetIcon = icons.TargetList, classStyle = icons.ClassStyleList }
    local list = lists[key]()
    setting(key .. "Choice"):SetValue(GamepadReticleCustomizer.ChoiceIndex(list, id))
end

-- The settings page

test("its page under Options > AddOns, in order, with the defaults; /grc opens it", function()
    boot()
    eq(game.category.name, "Gamepad Reticle Customizer")
    eq(controlList(), "checkbox:Enable, slider:Size, swatch:Color, button:(Reset color), slider:Border, "
        .. "swatch:Border color, button:(Reset border color), "
        .. "slider:On a target, button:Class icons, slider:Icon size, button:Camera over shoulder, button:Reticle on your target",
        "without Jiberish Fabled Icons: no one-choice Reticle or Class icons slider; its button in the Class icons row")
    boot({ jiberish = true })
    eq(controlList(), "checkbox:Enable, slider:Reticle, slider:Size, swatch:Color, button:(Reset color), slider:Border, "
        .. "swatch:Border color, button:(Reset border color), "
        .. "slider:On a target, slider:Class icons, slider:Icon size, button:Camera over shoulder, button:Reticle on your target",
        "with it: both sliders, no button")
    boot()
    local saved = GamepadReticleCustomizerDB
    eq(saved.enabled, true); eq(saved.color, "FFFFFFFF"); eq(saved.size, 4); eq(saved.borderSize, 0)
    eq(saved.borderColor, "000000FF"); eq(saved.icon, "dot")
    eq(saved.targetIcon, "none", "nothing on a target by default"); eq(saved.iconSize, 32)
    eq(control("slider", "Size").extra.format(4), "4 (default)"); eq(control("slider", "Size").extra.format(24), "24")
    eq(control("slider", "Border").extra.format(0), "Off"); eq(control("slider", "Border").extra.format(3), "3")
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("")
    eq(game.opened, 42)
end)

-- Drawing

test("at login: our reticle drawn on the game's, the game's dot see-through, your settings on it", function()
    boot({ saved = { color = "C351B4E4", size = 10 } })
    eq(layer().parent, GamepadReticle.Icons, "a child of the game's Icons: shows, hides and fades with it")
    eq(layer().relativeTo, GamepadReticle.Icons.StandardIcon, "centered on the game's dot")
    eq(layer():IsShown(), true)
    eq(GamepadReticle.Icons.StandardIcon:GetAlpha(), 0, "the game's dot see-through, not hidden or changed")
    eq(GamepadReticle.Icons.StandardIcon.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "its texture untouched")
    eq(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "the game's dot shape")
    eq(layer().shape:GetWidth(), 10)
    eq(colorOf(layer().shape), string.format("%.2f %.2f %.2f %.2f", 0xC3 / 255, 0x51 / 255, 0xB4 / 255, 0xE4 / 255))
    eq(layer().border:IsShown(), false, "no border by default")
end)

test("Enable off puts the game's dot back at its own alpha; on draws ours again", function()
    boot({ gameDotAlpha = 0.7 })
    setting("enabled"):SetValue(false)
    eq(layer():IsShown(), false)
    eq(GamepadReticle.Icons.StandardIcon:GetAlpha(), 0.7, "the alpha it had before we first drew")
    setting("enabled"):SetValue(true)
    eq(layer():IsShown(), true); eq(GamepadReticle.Icons.StandardIcon:GetAlpha(), 0)
end)

test("size and border: the slider values, clamped; border 0 hides it", function()
    boot()
    setting("size"):SetValue(24)
    eq(layer().shape:GetWidth(), 24); eq(layer().shape:GetHeight(), 24)
    setting("borderSize"):SetValue(3)
    eq(layer().border:IsShown(), true)
    eq(layer().border:GetWidth(), 30, "the size plus the border on each side")
    eq(layer().border.texture, layer().shape.texture, "the same shape, behind it")
    eq(colorOf(layer().border), "0.00 0.00 0.00 1.00", "black by default")
    setting("borderSize"):SetValue(0)
    eq(layer().border:IsShown(), false)
    setting("size"):SetValue(500)
    eq(layer().shape:GetWidth(), 64, "clamped to the slider's end")
    setting("size"):SetValue("nonsense")
    eq(layer().shape:GetWidth(), 4, "not a number: the default")
end)

-- Colors

test("the color: 32 bits RRGGBBAA from /grc, six digits opaque, a wrong one changes nothing", function()
    boot()
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("FF3030CC")
    eq(GamepadReticleCustomizerDB.color, "FF3030CC")
    eq(colorOf(layer().shape), "1.00 0.19 0.19 0.80", "drawn at once")
    eq(game.printed[#game.printed]:find("FF3030CC", 1, true) ~= nil, true, "and says so")
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("nonsense")
    eq(GamepadReticleCustomizerDB.color, "FF3030CC", "a wrong color changes nothing")
    eq(game.printed[#game.printed]:find("usage", 1, true) ~= nil, true, "and says how")
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("#00ff00")
    eq(GamepadReticleCustomizerDB.color, "00FF00FF", "six digits: opaque")
end)

test("the two swatches speak AARRGGBB, each for its own color; the opacity is kept", function()
    boot({ saved = { color = "00FF0066", borderSize = 2 } })
    local colorSwatch, borderSwatch = control("swatch", "Color").setting, control("swatch", "Border color").setting
    eq(colorSwatch.getValue(), "FF00FF00", "alpha FF, the color")
    colorSwatch.setValue("ff0000ff")
    eq(GamepadReticleCustomizerDB.color, "0000FF66", "the picked color, the opacity kept")
    colorSwatch.setValue("nonsense")
    eq(GamepadReticleCustomizerDB.color, "0000FF66", "a wrong value changes nothing")
    borderSwatch.setValue("ffffffff")
    eq(GamepadReticleCustomizerDB.borderColor, "FFFFFFFF", "the border's own color")
    eq(GamepadReticleCustomizerDB.color, "0000FF66", "the reticle's untouched")
    eq(colorOf(layer().border), "1.00 1.00 1.00 1.00", "drawn at once")
end)

test("the picker's opacity bar is for the color whose swatch opened it", function()
    boot({ saved = { color = "FFFFFF80", borderColor = "00000040", borderSize = 1 } })
    control("swatch", "Border color").setting.getValue()
    ColorPickerFrame:Show()
    near(game.picker.alpha, 0x40 / 255, "the border's opacity on the bar")
    ColorPickerFrame.Content.ColorPicker:SetColorAlpha(1); ColorPickerFrame.opacityFunc()
    eq(GamepadReticleCustomizerDB.borderColor, "000000FF", "the bar sets the border's")
    eq(GamepadReticleCustomizerDB.color, "FFFFFF80", "not the reticle's")
    ColorPickerFrame:Hide()
    game.time = game.time + 5
    control("swatch", "Color").setting.getValue()
    ColorPickerFrame:Show()
    near(game.picker.alpha, 0x80 / 255, "then the reticle's own")
end)

test("controller: while the picker is open for our color, the sticks and D-pad drive it", function()
    boot()
    local driver = GamepadReticleCustomizer.PickerSticks.driver
    local function step(seconds) driver.scripts.OnUpdate(driver, seconds) end
    ColorPickerFrame:Show()
    eq(driver.shown, false, "a picker opened by something else (the chat settings): left to the game")
    eq(ColorPickerFrame.hasOpacity, nil, "and no opacity bar put on it")
    ColorPickerFrame:Hide()
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("FFFFFF80")
    control("swatch", "Color").setting.getValue()   -- the swatch reads the color as it opens the picker
    game.time = game.time + 0.1
    ColorPickerFrame:Show()
    eq(driver.shown, true, "opened for the reticle color")
    eq(ColorPickerFrame.hasOpacity, true, "the opacity bar put on the picker")
    near(game.picker.alpha, 128 / 255, "at the reticle's opacity")
    game.padUp = true; step(0.5)
    near(game.picker.alpha, 128 / 255 + 0.25, "D-pad up: more solid (0.5 a second)")
    eq(GamepadReticleCustomizerDB.color:sub(7, 8), string.format("%02X", math.floor((128 / 255 + 0.25) * 255 + 0.5)),
        "and the reticle with it")
    game.padUp, game.padDown = false, true; step(10)
    near(game.picker.alpha, 0, "D-pad down: see-through, not past 0")
    game.padDown = false
    game.cameraStickY = 1; step(0.5)
    near(game.picker.hsv[3], 0.8, "right stick up: brighter (0.6 a second)")
    game.cameraStickY = -1; step(5)
    near(game.picker.hsv[3], 0, "right stick down: darker, not past black")
    game.cameraStickY = 0
    game.picker.hsv = { 0, 0, 1 }
    game.moveStickX = -1; step(0.5)
    near(game.picker.hsv[2], 0.4, "left stick: out from the middle (0.8 a second)")
    game.moveStickX, game.moveStickY = -1, 0; step(10)
    near(game.picker.hsv[2], 1, "never past the wheel's edge")
    game.moveStickX = 0
    ColorPickerFrame:Hide()
    eq(driver.shown, false, "picker shut: nothing runs")
end)

test("keyboard: the picker gets the opacity bar but no stick driver", function()
    boot({ keyboard = true })
    control("swatch", "Color").setting.getValue()
    ColorPickerFrame:Show()
    eq(ColorPickerFrame.hasOpacity, true)
    eq(GamepadReticleCustomizer.PickerSticks.driver.shown, false)
end)

-- Shapes

test("the reticle: the game's dot, no Jiberish shapes without it; a Jiberish id without it falls back to the dot", function()
    boot()
    eq(control("slider", "Reticle"), nil, "one choice only: no slider")
    GamepadReticleCustomizerDB.icon = "jiberish:x-bold"; GamepadReticleCustomizer.UpdateReticle()
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot")
end)

test("with Jiberish Fabled Icons installed: its 16 reticles listed and drawn from its folder, credited, no install button", function()
    boot({ jiberish = true })
    local labels = choiceLabels("Reticle")
    eq(#labels, 17, "the dot and 16 Jiberish shapes")
    eq(labels[2], "Circle (bold)"); eq(labels[8], "Split plus (bold)"); eq(labels[17], "X (thin)")
    choose("icon", "jiberish:splitplus-thin")
    eq(GamepadReticleCustomizerDB.icon, "jiberish:splitplus-thin", "the slider's step saved as the shape's id")
    eq(layer().shape.texture, "Interface\\AddOns\\JiberishIcons\\Media\\Crosshair\\splitplus-thin-128")
    eq(control("button", "Class icons"), nil, "no install button when it's there")
    eq(control("slider", "Reticle").extra.tooltip:find("Shapes from Jiberish Fabled Icons", 1, true) ~= nil, true,
        "credited, as its license asks")
end)

test("choices are sliders (a dropdown's menu breaks on the controller): on a target, none, a player's class, by target, the 8 raid markers, then the game's icons", function()
    boot()
    local labels = choiceLabels("On a target")
    eq(#labels, 11 + 12)
    eq(labels[1], "None"); eq(labels[2], "Target Class"); eq(labels[3], "By target")
    eq(labels[11], "Raid marker: Skull"); eq(labels[12], "Icon: Sniper scope"); eq(labels[23], "Icon: Holy")
    choose("targetIcon", "marker8")
    eq(GamepadReticleCustomizerDB.targetIcon, "marker8")
    setTarget({ isPlayer = false, reaction = 2 })
    choose("targetIcon", "icon:scope")
    eq(layer().shape.texture, "Interface\\Icons\\Ability_Hunter_SniperShot", "a game icon on the target")

    boot({ saved = { targetIcon = "class", icon = "dot" } })
    eq(GamepadReticleCustomizer.choices.targetIcon, 2, "the slider starts at your saved choice")
end)

test("icons show only while you have a target, at the icon size, in their own colors; the reticle comes back", function()
    boot({ saved = { color = "FF3030FF", size = 6, targetIcon = "marker8", iconSize = 30, borderSize = 2 } })
    eq(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "no target: the reticle")
    eq(layer().shape:GetWidth(), 6); eq(colorOf(layer().shape), "1.00 0.19 0.19 1.00")
    setTarget({ isPlayer = false, reaction = 2 })
    eq(layer().shape.texture, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", "a target: the skull")
    eq(layer().shape:GetWidth(), 30, "at the icon size")
    eq(colorOf(layer().shape), "1.00 1.00 1.00 1.00", "in its own colors")
    eq(layer().border:GetWidth(), 34, "the border around it")
    eq(layer().shape.texCoord[2], 1, "shown whole")
    setTarget(nil)
    eq(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "target gone: the reticle back")
    eq(layer().shape:GetWidth(), 6); eq(colorOf(layer().shape), "1.00 0.19 0.19 1.00")
end)

test("a player's class icon: the game's classicon atlas for players; NPCs, an unknown class or a missing atlas keep the reticle", function()
    boot({ saved = { targetIcon = "class" } })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5 })
    eq(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-mage")
    eq(layer().shape.texture, "classicons-file", "drawn as the atlas's file")
    eq(table.concat(layer().shape.texCoord, ","), "0.5,0.75,0.25,0.5", "and its cell")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "class")
    eq(layer().shape:GetWidth(), 32)
    setTarget({ isPlayer = true, classFile = "DRUID", reaction = 2 })
    eq(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-druid", "an enemy player too")
    setTarget({ isPlayer = false, reaction = 4 })
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "an NPC: the reticle")
    eq(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "the dot's texture")
    eq(table.concat(layer().shape.texCoord, ","), "0,1,0,1", "shown whole again")
    setTarget({ isPlayer = true, classFile = nil, reaction = 5 })
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "class unknown (hidden): the reticle")
    boot({ saved = { targetIcon = "class" }, classAtlases = false })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5 })
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "no such atlas on this client: the reticle")
end)

test("a target without a nameplate on screen (a vendor, a minion, off screen) keeps the reticle; its nameplate coming brings the icon", function()
    boot({ saved = { targetIcon = "marker8", iconSize = 30 } })
    setTarget({ isPlayer = false, reaction = 5, nameplate = false, plateUnit = "nameplate4" })
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "a vendor with friendly NPC nameplates off: the reticle")
    game.target.nameplate = true
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "marker8", "its nameplate shows: the icon")
    game.target.nameplate = false
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "marker8", "another unit's nameplate: nothing redrawn")
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate4")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "the target off screen: the reticle back")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5, nameplate = false })
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "a player with friendly nameplates off: the reticle")
end)

test("a client without an atlas file: SetAtlas, after resetting the cell a Jiberish style left", function()
    boot({ jiberish = true, saved = { targetIcon = "class", classStyle = "jiberish:fabled" } })
    _G.C_Texture.GetAtlasInfo = function(atlas) if atlas:find("^classicon%-") then return {} end end
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 5 })
    eq(table.concat(layer().shape.texCoord, ","), "0.25,0.375,0.125,0.25", "the Jiberish cell")
    choose("classStyle", "game")
    eq(layer().shape.atlas, "classicon-priest")
    eq(table.concat(layer().shape.texCoord, ","), "0,1,0,1", "reset before SetAtlas")
end)

test("old settings: a marker in the single Shape becomes the icon on a target; a custom texture becomes none", function()
    boot({ saved = { icon = "marker2" } })
    eq(GamepadReticleCustomizerDB.icon, "dot"); eq(GamepadReticleCustomizerDB.targetIcon, "marker2")
    boot({ saved = { targetIcon = "custom", customTexture = "Interface\\Icons\\INV_Misc_QuestionMark" } })
    eq(GamepadReticleCustomizerDB.targetIcon, "none", "no texture paths any more"); eq(GamepadReticleCustomizerDB.customTexture, nil)
    boot({ saved = { icon = "custom", customTexture = 136243 } })
    eq(GamepadReticleCustomizerDB.targetIcon, "none", "the oldest shape setting, custom: none too"); eq(GamepadReticleCustomizerDB.icon, "dot")
    boot({ saved = { icon = "jiberish:x-bold" } })
    eq(GamepadReticleCustomizerDB.icon, "jiberish:x-bold", "a reticle shape stays"); eq(GamepadReticleCustomizerDB.targetIcon, "none")
end)

test("Jiberish Fabled Icons installed but turned off: not offered, its choices fall back, a button tells how to turn it on", function()
    boot({ jiberishOff = true, saved = { icon = "jiberish:x-bold", size = 24, targetIcon = "class", classStyle = "jiberish:fabled" } })
    eq(control("slider", "Reticle"), nil, "its shapes aren't offered")
    eq(control("slider", "Class icons"), nil, "nor its styles")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "a saved Jiberish shape falls back to the dot")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5 })
    eq(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-mage", "and a Jiberish class style to the game's")
    eq(GamepadReticleCustomizerDB.icon, "jiberish:x-bold", "your choice kept for when it's on again")
    local button = control("button", "Class icons")
    eq(button.extra.buttonText, "Enable Jiberish Fabled Icons", "not Get: it's installed")
    button.extra.onClick()
    eq(popup():IsShown(), true, "the game-style popup")
    eq(popup().Border.template, "DialogBorderTemplate", "the game's dialog border")
    eq(popup().text.text:find("turned off", 1, true) ~= nil, true, popup().text.text)
    eq(popup().editBox:IsShown(), false, "a message: nothing to copy")
    eq(popupButtons(), "Not now, [secure] Turn on and reload")
    clickPopupButton("Turn on and reload")
    eq(game.enabledAddOn.name, "JiberishIcons", "turned on")
    eq(game.enabledAddOn.character, "Player-93-0A1B2C3D", "for this character, by its GUID as the AddOns list does (not its name)")
    eq(game.enabledAddOn.saved, true, "saved before the reload, as the AddOns list does (or it stays off)")
    eq(game.reloaded, "/reload", "then reloaded by the secure button")
end)

test("without it: the install button shows the link to copy", function()
    boot()
    eq(control("button", "Class icons").extra.buttonText, "Get Jiberish Fabled Icons", "in the Class icons row")
    control("button", "Class icons").extra.onClick()
    eq(popup():IsShown(), true)
    eq(popup().editBox:GetText(), "https://www.curseforge.com/wow/addons/jiberish-fabled-icons")
    eq(popup().editBox.highlighted, true, "selected, ready for Ctrl+C")
    eq(popupButtons(), "Close, [secure] Reload", "a Reload for once it's installed")
    clickPopupButton("Close")
    eq(popup():IsShown(), false)
end)

test("no icon picker and no texture paths: no Choose icon button, /grc texture is just a wrong color", function()
    boot()
    eq(control("button", "Choose icon"), nil)
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("texture Interface\\Icons\\Spell_Nature_Starfall")
    eq(game.printed[#game.printed]:find("usage: /grc RRGGBBAA", 1, true) ~= nil, true, game.printed[#game.printed])
    eq(GamepadReticleCustomizer.IconPicker, nil)
end)

test("tooltips: text after a colon is a list (each line after \":\" a \"•\" line), for legibility", function()
    for _, jiberish in ipairs({ true, false }) do
        boot({ jiberish = jiberish })
        for _, entry in ipairs(game.controls) do
            local tooltip = entry.extra and entry.extra.tooltip
            local name = (entry.setting and entry.setting.label) or entry.extra.name or "?"
            if type(tooltip) == "string" then
                for line in tooltip:gmatch("[^\n]+") do
                    if not line:find("^• ") then
                        -- A colon outside a list line ends the line: what follows is a list.
                        local afterColon = line:gsub("https?://", ""):match(":%s*(.+)$")
                        eq(afterColon, nil, name .. ": \"" .. line .. "\"")
                    end
                end
                eq(tooltip:find("preview shows", 1, true), nil, name .. ": no telling what the preview shows")
            end
        end
    end
end)

test("every choice slider's label fits the slider (22 characters, seen cut in game beyond)", function()
    boot({ jiberish = true })
    local maxLength = GamepadReticleCustomizer.Icons.LABEL_MAX_LENGTH
    for _, slider in ipairs({ "Reticle", "On a target", "Class icons" }) do
        for _, label in ipairs(choiceLabels(slider)) do
            eq(#label <= maxLength, true, slider .. ": \"" .. label .. "\" is " .. #label .. " characters")
        end
    end
end)

test("the dot and the shapes keep their own sizes: a shape starts at 32, the dot gets its own back", function()
    boot({ jiberish = true, saved = { size = 6 } })
    choose("icon", "jiberish:x-bold")
    eq(GamepadReticleCustomizerDB.size, 32, "a shape starts at 32: at the dot's size it can't be seen")
    setting("size"):SetValue(40)
    choose("icon", "jiberish:plus-thin")
    eq(GamepadReticleCustomizerDB.size, 40, "shape to shape: the size kept")
    choose("icon", "dot")
    eq(GamepadReticleCustomizerDB.size, 6, "back to the dot: the dot's own size, not 24 or 40")
    eq(layer().shape:GetWidth(), 6)
    choose("icon", "jiberish:x-thin")
    eq(GamepadReticleCustomizerDB.size, 40, "back to a shape: the shapes' size")
end)

test("the reset rows' label is one space: blank, yet not \"\", so the game lines the button up with the others", function()
    boot()
    eq(control("button", "Reset color").extra.name, " ")
    eq(control("button", "Reset border color").extra.name, " ")
end)

test("each color has its own reset: the reticle's to white, the border's to black", function()
    boot({ saved = { color = "FF3030CC", borderColor = "00FF00FF", borderSize = 2 } })
    control("button", "Reset color").extra.onClick()
    eq(GamepadReticleCustomizerDB.color, "FFFFFFFF"); eq(colorOf(layer().shape), "1.00 1.00 1.00 1.00")
    eq(GamepadReticleCustomizerDB.borderColor, "00FF00FF", "the border's untouched")
    control("button", "Reset border color").extra.onClick()
    eq(GamepadReticleCustomizerDB.borderColor, "000000FF"); eq(colorOf(layer().border), "0.00 0.00 0.00 1.00")
end)

test("class icon styles: the game's, or a Jiberish Fabled Icons class sheet's cell for the class; without it, the game's", function()
    boot()
    eq(control("slider", "Class icons"), nil, "without Jiberish Fabled Icons: no slider, the game's icons only")
    boot({ jiberish = true, saved = { targetIcon = "class" } })
    local labels = choiceLabels("Class icons")
    eq(#labels, 12, "the game's and 11 Jiberish styles")
    eq(labels[2], "Fabled"); eq(labels[3], "Fabled Class"); eq(labels[4], "Fabled Pixels")
    choose("classStyle", "jiberish:fabledpixels")
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 5 })
    eq(layer().shape.texture, "Interface\\AddOns\\JiberishIcons\\Media\\Class\\fabledpixels")
    eq(table.concat(layer().shape.texCoord, ","), "0.25,0.375,0.125,0.25", "the Priest's cell: column 3, row 2 of 8")
    setTarget({ isPlayer = true, classFile = "DEMONHUNTER", reaction = 2 })
    eq(table.concat(layer().shape.texCoord, ","), "0.375,0.5,0.25,0.375")
    choose("classStyle", "game")
    eq(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-demonhunter", "the game's again")
    eq(layer().shape.texture, "classicons-file")
    eq(table.concat(layer().shape.texCoord, ","), "0.5,0.75,0.25,0.5",
        "the game's cell, not the Jiberish one left behind (seen in game)")
    boot({ saved = { targetIcon = "class", classStyle = "jiberish:fabled" } })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5 })
    eq(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-mage", "a Jiberish style without the addon: the game's icon")
end)

test("without Gamepad Reticle On Target: a button shows its link to copy; with it, no button", function()
    boot()
    control("button", "Reticle on your target").extra.onClick()
    eq(control("button", "Reticle on your target").extra.buttonText, "Get the addon")
    eq(popup().editBox:GetText(), "https://www.curseforge.com/projects/1819101")
    eq(popup().editBox.highlighted, true, "selected, ready for Ctrl+C")
    eq(popupButtons(), "Close, [secure] Reload")
    boot({ reticleOnTargetInstalled = true })
    eq(control("button", "Reticle on your target"), nil, "installed: no button")
end)

test("on the controller: A clicks the popup's first button, B the last, a hint says so; closing gives them back", function()
    boot()
    control("button", "Class icons").extra.onClick()   -- Get Jiberish Fabled Icons: Reload, Close
    eq(game.bindings.PAD1, "GamepadReticleCustomizerPopupReload", "A: the first button, Reload")
    eq(game.bindings.PAD2, "GamepadReticleCustomizerPopupButton1", "B: the last, Close")
    eq(popup().reloadButton.controllerIcon.atlas, "gamepad-test-pad1", "the A icon on Reload, as the game marks its buttons")
    eq(popup().buttons[1].controllerIcon.atlas, "gamepad-test-pad2", "the B icon on Close")
    eq(popup().hint.text, "", "the icons say it: no hint line")
    _G[game.bindings.PAD2]:Click()
    eq(popup():IsShown(), false, "B closed it")
    eq(game.bindings.PAD1, nil, "the controller's buttons given back"); eq(game.bindings.PAD2, nil)
    eq(game.bindings["ALT-CTRL-SHIFT-C"] ~= nil, true, "other bindings untouched")

    boot({ noControllerIcons = true })
    control("button", "Class icons").extra.onClick()
    eq(popup().hint.text, "A: Reload      B: Close", "no icons on this client: said in words")

    boot({ keyboard = true })
    control("button", "Class icons").extra.onClick()
    eq(game.bindings.PAD1, nil, "keyboard: no controller bindings"); eq(popup().hint.text, "")
    eq(popup().reloadButton.controllerIcon:IsShown(), false, "and no icons")
end)

test("in a fight, a popup (it holds a secure Reload) opens once the fight is over", function()
    boot()
    game.combat = true
    eq(GamepadReticleCustomizer.Popup.Show({ text = "Hello", buttons = { { text = "Reload", reload = true } } }), false)
    eq(popup(), nil, "not built in combat")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    eq(popup():IsShown(), true, "after the fight")
    eq(popup().text.text, "Hello")
end)

-- The preview beside the settings page

local function showPage(category)
    SettingsPanel.shown, game.currentCategory = category ~= nil, category
    local watcher = GamepadReticleCustomizer.Preview.watcher
    watcher.scripts.OnUpdate(watcher, 1)
end

test("the preview shows beside our settings page only, with the reticle and the icon on a target as drawn", function()
    boot({ saved = { color = "FF3030FF", size = 10, targetIcon = "marker8", iconSize = 30, borderSize = 2 } })
    local preview = GamepadReticleCustomizer.Preview.frame
    eq(preview.parent, SettingsPanel, "on the settings window")
    eq(preview.Bg.template, "FlatPanelBackgroundTemplate", "the settings window's own background")
    eq(preview.NineSlice.template, "NineSlicePanelTemplate"); eq(preview.NineSlice.layoutName, "ButtonFrameTemplateNoPortrait",
        "and its metal border")
    eq(preview.reticle.template, "InsetFrameTemplate", "each cell an inset, as inside the game's windows")
    eq(preview.title.text, "Preview")
    eq(preview:IsShown(), false, "hidden until the page opens")
    showPage({ name = "Another page" })
    eq(preview:IsShown(), false, "another page: hidden")
    showPage(game.category)
    eq(preview:IsShown(), true, "our page: shown")
    local width, height = preview:GetWidth(), preview:GetHeight()
    eq(preview.reticle.shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    -- Zoomed: the reticle and its border fill 80% of the 120 cell (96): 10 + 2 x 2 = 14 wide becomes 96.
    near(preview.reticle.border:GetWidth(), 96, "zoomed to fill the cell"); near(preview.reticle.shape:GetWidth(), 96 * 10 / 14)
    eq(colorOf(preview.reticle.shape), "1.00 0.19 0.19 1.00")
    eq(preview.reticle.realShape:GetWidth(), 10, "and at its real size in the corner")
    eq(preview.reticle.realBorder:GetWidth(), 14)
    eq(preview.onTarget.shape.texture, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    near(preview.onTarget.border:GetWidth(), 96, "an icon zoomed the same")
    near(preview.onTarget.realBorder:GetWidth(), 32, "an icon bigger than the corner: shrunk to fit it (40 x 80%)")
    setting("size"):SetValue(20)
    eq(preview.reticle.realShape:GetWidth(), 20, "redrawn on a change")
    near(preview.reticle.border:GetWidth(), 96, "the zoomed view still fills the cell")
    eq(preview:GetWidth(), width); eq(preview:GetHeight(), height, "the window keeps its size")
    choose("targetIcon", "class")
    eq(preview.onTarget.shape.texture, "classicons-file", "a player's class: your own as the example")
    choose("targetIcon", "none")
    eq(preview.onTarget.label.text, "On a target: the reticle stays")
    eq(preview.onTarget.shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    setting("enabled"):SetValue(false)
    eq(preview.alpha, 0.5, "the addon off: dimmed")
    showPage(nil)
    eq(preview:IsShown(), false, "the window closed: hidden")
end)

-- /grc debug, run here against the fake game

local function failedChecks(run)
    local lines = {}
    for _, check in ipairs(run.checks) do
        if check.result == "fail" then
            lines[#lines + 1] = check.name .. ": expected " .. tostring(check.expected) .. ", got " .. tostring(check.actual)
        end
    end
    return table.concat(lines, "\n")
end

-- Plays the outside (tests/screenshot_debug.sh's keys, or you): answers the
-- corner square. Blue: selects the next friendly player; violet: the next NPC;
-- navy: clears the target. Returns once the run's timers are done.
local function driveDebugRun(friendlyPlayers, npcs)
    local friendlyIndex, npcIndex = 0, 0
    for _ = 1, 20000 do
        if #game.timers == 0 then return end
        local marker = GamepadReticleCustomizer.Debug.marker
        local color = marker and marker:IsShown() and colorOf(marker.texture)
        if color == "0.00 0.00 1.00 1.00" and friendlyIndex < #friendlyPlayers then
            friendlyIndex = friendlyIndex + 1; setTarget(friendlyPlayers[friendlyIndex])
        elseif color == "0.50 0.00 1.00 1.00" and npcIndex < #npcs then
            npcIndex = npcIndex + 1; setTarget(npcs[npcIndex])
        elseif color == "0.00 0.00 0.50 1.00" and game.target then
            setTarget(nil)
        end
        frame()
    end
    error("the debug run never ended")
end

local function checkResult(run, wanted)
    for _, check in ipairs(run.checks) do
        if check.name:find(wanted, 1, true) then return check.result end
    end
end

test("/grc debug: every look checked, on 3 friendly classes and both NPC kinds, your settings back, the reload box", function()
    for _, jiberish in ipairs({ false, true }) do
        boot({ jiberish = jiberish, saved = { color = "3961CDFF", size = 7, targetIcon = "marker2" } })
        SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
        local debugSuite = GamepadReticleCustomizer.Debug
        driveDebugRun({ { isPlayer = true, classFile = "WARRIOR", reaction = 5 }, { isPlayer = true, classFile = "WARRIOR", reaction = 5 },
            { isPlayer = true, classFile = "MAGE", reaction = 5 }, { isPlayer = true, classFile = "PRIEST", reaction = 5 } },
            { { isPlayer = false, reaction = 2 }, { isPlayer = false, reaction = 4 } })
        local run = GamepadReticleCustomizerDebugDB.runs[1]
        eq(failedChecks(run), "", "no failed check (Jiberish " .. tostring(jiberish) .. ")")
        eq(run.failed, 0)
        eq(run.found.class1, "WARRIOR"); eq(run.found.class2, "MAGE", "the second Warrior skipped: a class already seen")
        eq(run.found.class3, "PRIEST"); eq(run.found.class4, nil, "no fourth class near")
        eq(run.found.npc1, "enemy"); eq(run.found.npc2, "neutral", "both kinds")
        eq(checkResult(run, "friendly player 2: its class icon, size 32 (MAGE): its nameplate shows the class's color"), "pass")
        eq(checkResult(run, "(within 60 s)"), "pass")
        eq(run.passed > 150, true, "passed " .. run.passed)
        eq(run.steps[3].onScreen.x, 1200, "where the reticle is, in screen pixels")
        eq(debugSuite.marker:IsShown(), false, "the square gone: done")
        eq(GamepadReticleCustomizerDB.color, "3961CDFF", "your settings back")
        eq(GamepadReticleCustomizerDB.size, 7); eq(GamepadReticleCustomizerDB.targetIcon, "marker2")
        eq(GamepadReticleCustomizerDebugDB.settingsToRestore, nil)
        eq(popup():IsShown(), true, "the reload popup")
        eq(popupButtons(), "Later, [secure] Reload")
    end
end)

test("/grc debug: alone (yourself, one NPC kind, no nameplates: the reticle stays), the optional parts are skipped, nothing fails", function()
    boot({ noNameplates = true })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    driveDebugRun({ { isPlayer = true, classFile = "DRUID", reaction = 5 } }, { { isPlayer = false, reaction = 4 } })
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    eq(failedChecks(run), "", "nothing failed")
    eq(run.found.class2, nil); eq(run.found.npc1, "neutral"); eq(run.found.npc2, nil)
    eq(checkResult(run, "its nameplate shows the class's color"), nil, "no nameplate: no class icon, nothing to compare")
    eq(checkResult(run, "target: its class icon, size 32 (DRUID): what's drawn"), "pass", "checked as the reticle staying")
    eq(checkResult(run, "the other kind of NPC"), "skip")
end)

test("/grc debug: an offered game icon missing on the client fails its check", function()
    boot()
    table.insert(GamepadReticleCustomizer.Icons.GAME_ICONS, { key = "gone", name = "Gone", file = "Interface\\Icons\\missing_icon" })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    driveDebugRun({ { isPlayer = true, classFile = "MAGE", reaction = 5 } }, { { isPlayer = false, reaction = 2 } })
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    eq(checkResult(run, "every game icon offered exists on this client"), "fail")
    table.remove(GamepadReticleCustomizer.Icons.GAME_ICONS)
end)

test("/grc friendly runs only the friendly player part, then the target cleared", function()
    boot({ saved = { color = "3961CDFF" } })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("friendly")
    driveDebugRun({ { isPlayer = true, classFile = "WARRIOR", reaction = 5 }, { isPlayer = true, classFile = "MAGE", reaction = 5 } },
        { { isPlayer = false, reaction = 2 } })
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    eq(run.name, "friendly")
    eq(failedChecks(run), "", "nothing failed")
    eq(run.found.class1, "WARRIOR"); eq(run.found.class2, "MAGE")
    eq(run.found.npc1, nil, "no NPC part")
    eq(checkResult(run, "dot, size 12, red"), nil, "no reticle-only part")
    eq(checkResult(run, "target cleared: the reticle back"), "pass", "ends with the target cleared")
    eq(GamepadReticleCustomizerDB.color, "3961CDFF", "your settings back")
    eq(popup():IsShown(), true, "the reload popup")
end)

test("/grc monsters runs only the NPC part, then the target cleared", function()
    boot()
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("monsters")
    driveDebugRun({ { isPlayer = true, classFile = "WARRIOR", reaction = 5 } },
        { { isPlayer = false, reaction = 4 }, { isPlayer = false, reaction = 1 } })
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    eq(run.name, "monsters")
    eq(failedChecks(run), "", "nothing failed")
    eq(run.found.npc1, "neutral"); eq(run.found.npc2, "enemy")
    eq(run.found.class1, nil, "no friendly part")
    eq(checkResult(run, "target cleared: the reticle back"), "pass")
end)

test("in the release (no Debug.lua), /grc friendly and /grc monsters open the settings", function()
    boot({ releaseBuild = true })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("friendly")
    eq(game.opened, 42)
    game.opened = nil
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("monsters")
    eq(game.opened, 42)
end)

test("/grc debug: no friendly player selected within 60 s fails; its keys are bound", function()
    boot()
    eq(game.bindings["ALT-CTRL-SHIFT-Y"], "GamepadReticleCustomizerDebugTarget")
    eq(game.bindings["ALT-CTRL-SHIFT-Z"], "GamepadReticleCustomizerDebugTargetEnemy")
    eq(game.bindings["ALT-CTRL-SHIFT-X"], "GamepadReticleCustomizerDebugClearTarget")
    eq(GamepadReticleCustomizerDebugTarget.attributes.macrotext, "/targetfriendplayer\n/target [noexists] player")
    eq(GamepadReticleCustomizerDebugTargetEnemy.attributes.macrotext, "/targetenemy")
    eq(GamepadReticleCustomizerDebugClearTarget.attributes.macrotext, "/cleartarget")
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    driveDebugRun({}, {})
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    eq(checkResult(run, "select a friendly player (within 60 s)"), "fail")
end)

test("/grc debug: waits for the reticle on screen before its first step (the cursor hides it)", function()
    boot()
    GamepadReticle.Icons:Hide()   -- the cursor shows, as just after a reload
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    local debugSuite = GamepadReticleCustomizer.Debug
    eq(colorOf(debugSuite.marker.texture), "1.00 1.00 0.00 1.00", "yellow: waiting")
    frame(); frame(); frame()
    eq(colorOf(debugSuite.marker.texture), "1.00 1.00 0.00 1.00", "still waiting, no step yet")
    GamepadReticle.Icons:Show()
    frame(); frame()
    eq(math.floor(debugSuite.marker.texture.color[3] * 255 + 0.5), 16,
        "once it shows: step 2 (step 1, waiting for no target, passed at once)")
    runUntilNoTimersLeft()
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    eq(run.environment.reticleWaitSeconds, 2, "waited 2 s (4 polls)")
    eq(run.environment.reticleOnScreenAtStart, true)

    boot()
    GamepadReticleCustomizer.Debug.WAIT_SECONDS = 1
    GamepadReticle.Icons:Hide()
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    runUntilNoTimersLeft()
    eq(GamepadReticleCustomizerDebugDB.runs[1].environment.reticleOnScreenAtStart, false, "never showed: runs anyway, says so")
end)

test("/grc debug: Alt+Ctrl+Shift+C starts it too (for the screenshot script)", function()
    boot()
    eq(game.bindings["ALT-CTRL-SHIFT-C"], "GamepadReticleCustomizerDebugStart")
    _G[game.bindings["ALT-CTRL-SHIFT-C"]]:Click()
    eq(#game.timers > 0, true, "running")
    driveDebugRun({ { isPlayer = true, classFile = "MAGE", reaction = 5 } }, { { isPlayer = false, reaction = 2 } })
    eq(GamepadReticleCustomizerDebugDB.runs[1].failed, 0)
end)

test("/grc debug: a fight stops it, your settings back, the square red", function()
    boot({ saved = { color = "3961CDFF" } })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    frame(); frame()
    game.combat = true
    game.fire("PLAYER_REGEN_DISABLED")
    eq(GamepadReticleCustomizerDebugDB.runs[1].stopped, "combat")
    eq(GamepadReticleCustomizerDB.color, "3961CDFF")
    eq(GamepadReticleCustomizer.Debug.marker.texture.color[1], 1, "red")
    runUntilNoTimersLeft()
    eq(#GamepadReticleCustomizerDebugDB.runs, 1, "nothing ran after the stop")
end)

test("/grc debug: a reload in the middle of a run puts your settings back at the next login", function()
    boot({ saved = { color = "FF0000FF", size = 48 },
        debugSaved = { runs = {}, settingsToRestore = { color = "3961CDFF", size = 7, enabled = true } } })
    eq(GamepadReticleCustomizerDB.color, "3961CDFF"); eq(GamepadReticleCustomizerDB.size, 7)
    eq(GamepadReticleCustomizerDebugDB.settingsToRestore, nil)
    eq(layer().shape:GetWidth(), 7, "and drawn")
end)

-- The addon and its release

test("an addon of its own: needs no other addon; listed under Gamepad", function()
    local toc = readFile("GamepadReticleCustomizer.toc")
    eq(toc:find("Dependencies", 1, true), nil); eq(toc:find("OptionalDeps", 1, true), nil)
    eq(toc:match("## Category: ([^\r\n]+)"), "Gamepad", "under Gamepad in the AddOns list, the game's own word")
end)

test("the release leaves Debug.lua out: ignored by .pkgmeta, and gone from the release .toc", function()
    assert(readFile(".pkgmeta"):find("\n  %- Debug%.lua\n"), ".pkgmeta ignores Debug.lua, alone on its line")
    eq(table.concat(tocFiles(true), ","),
        "SavedSettings.lua,Color.lua,Icons.lua,NpcJobs.lua,Target.lua,Reticle.lua,PickerSticks.lua,Popup.lua,Preview.lua,RelatedAddons.lua,GamepadReticleCustomizer.lua")
    eq(tocFiles()[#tocFiles()], "Debug.lua", "the repo's .toc loads it last")
end)

test("without Debug.lua (the release), the addon works and /grc debug opens the settings", function()
    boot({ releaseBuild = true })
    eq(GamepadReticleCustomizer.Debug, nil)
    eq(layer():IsShown(), true)
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    eq(game.opened, 42)
end)

test("the reticle left in the middle of the screen (nothing moves it): no icon, the reticle stays", function()
    boot({ reticleOnTarget = false, saved = { targetIcon = "marker8" } })
    game.fire("PLAYER_ENTERING_WORLD")
    setTarget({ isPlayer = false, reaction = 2, plateUnit = "nameplate4" })
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "a target with its nameplate, but the reticle in the middle")
    eq(GamepadReticleCustomizer.TargetInfo().reticleOnNameplate, false)
    -- Then something puts it under the nameplate (a restricted region: not measurable).
    GamepadReticle:SetPoint("CENTER", { restricted = true }, "BOTTOM")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "marker8", "redrawn as soon as it's moved there")
    GamepadReticle:SetPoint("CENTER", UIParent, "BOTTOM")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "and back in the middle: the reticle")
end)

test("the reticle on a nameplate that can be measured: the target's own counts, another frame doesn't", function()
    boot({ reticleOnTarget = false, saved = { targetIcon = "marker8" } })
    game.fire("PLAYER_ENTERING_WORLD")
    setTarget({ isPlayer = false, reaction = 2 })
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local healthBar = { GetParent = function() return plate end }
    C_NamePlate.GetNamePlateForUnit = function() return plate end
    GamepadReticle:SetPoint("CENTER", healthBar, "BOTTOM")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "marker8", "under a part of the target's nameplate")
    GamepadReticle:SetPoint("CENTER", { GetParent = function() return UIParent end }, "BOTTOM")
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "under some other frame")
end)

test("/grc and /gamepadreticlecustomizer", function()
    boot()
    eq(SLASH_GAMEPADRETICLECUSTOMIZER1, "/grc"); eq(SLASH_GAMEPADRETICLECUSTOMIZER2, "/gamepadreticlecustomizer")
end)

test("its icon in the AddOns list: Media/icon-64.png, shipped", function()
    local function readBytes(path) local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close(); return text end
    local toc = readBytes("GamepadReticleCustomizer.toc"):gsub("\r", "")
    eq(toc:match("## IconTexture: ([^\n]+)"), "Interface\\AddOns\\GamepadReticleCustomizer\\Media\\icon-64.png")
    eq(readBytes("Media/icon-64.png"):sub(2, 4), "PNG", "a PNG file")
    eq(readBytes(".pkgmeta"):find("- Media/icon-64.png", 1, true), nil, "not left out of the release")
end)

test("debug build: Gamepad Reticle On Target turned off counts as missing, to see its button; the release doesn't", function()
    boot({ reticleOnTargetOff = true })
    eq(control("button", "Reticle on your target").extra.buttonText, "Get the addon",
        "turned off for this character: the button, as players without it see it")
    boot({ reticleOnTargetOff = true, releaseBuild = true })
    eq(control("button", "Reticle on your target"), nil, "the release: installed is installed")
    boot({ reticleOnTargetInstalled = true })
    eq(control("button", "Reticle on your target"), nil, "debug build, turned on: no button")
end)

test("a Get button for each missing sibling, in order, each with its own CurseForge link", function()
    boot()
    eq(control("button", "Camera over shoulder").extra.buttonText, "Get the addon")
    control("button", "Camera over shoulder").extra.onClick()
    eq(popup().editBox:GetText(), "https://www.curseforge.com/projects/1818297")
    control("button", "Reticle on your target").extra.onClick()
    eq(popup().editBox:GetText(), "https://www.curseforge.com/projects/1819101")
    boot({ reticleOnTargetInstalled = true })
    eq(control("button", "Reticle on your target"), nil, "installed: its button gone")
    eq(control("button", "Camera over shoulder") ~= nil, true, "the other one still offered")
end)

-- "By target": an icon by kind of target.
local function drawnLook() local look = GamepadReticleCustomizer.Reticle.Drawn(); return look.atlas or look.texture end

test("By target: players their class, enemy players their faction, enemy NPCs crossed swords, neutral NPCs a question mark", function()
    boot({ saved = { targetIcon = "bytarget" } })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5, faction = "Horde" })
    eq(drawnLook(), "classicon-mage", "a friendly player: the class")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 2, faction = "Alliance" })
    eq(drawnLook(), "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", "an enemy player: the faction")
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 4, faction = "Alliance" })
    eq(drawnLook(), "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", "the other faction, unflagged on a PvE realm (neutral): still its faction")
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 1, faction = "Horde" })
    eq(drawnLook(), "classicon-priest", "your own faction, hostile (a duel): its class")
    setTarget({ isPlayer = false, reaction = 2 })
    eq(drawnLook(), "Crosshair_PVP_128", "an enemy NPC: crossed swords")
    setTarget({ isPlayer = false, reaction = 4 })
    eq(drawnLook(), "QuestTurnin", "a neutral NPC: a question mark")
end)

test("By target, friendly NPCs: their job's tracking icon, a class trainer's class, other trainers the profession one, else a speech bubble", function()
    boot({ saved = { targetIcon = "bytarget" } })
    setTarget({ isPlayer = false, reaction = 5, title = "Stable Master" })
    eq(drawnLook(), 136466, "the game's Stable Master tracking icon")
    setTarget({ isPlayer = false, reaction = 5, title = "Food & Drink" })
    eq(drawnLook(), 136459)
    setTarget({ isPlayer = false, reaction = 5, title = "Warrior Trainer" })
    eq(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-warrior", "a class trainer: its class")
    setTarget({ isPlayer = false, reaction = 5, title = "Cooking Trainer" })
    eq(drawnLook(), 136463, "another trainer: the profession trainers' icon")
    setTarget({ isPlayer = false, reaction = 5 })
    eq(drawnLook(), "Crosshair_Speak_128", "no title (its second line is its level): a speech bubble")
    setTarget({ isPlayer = false, reaction = 5, title = "Bluffwatcher Captain" })
    eq(drawnLook(), "Crosshair_Speak_128", "a title with no known job: a speech bubble")
    setTarget({ isPlayer = false, reaction = 5, controlled = true })
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "another player's pet: the reticle")
end)

test("By target on a client without those atlases: the game's icon files instead", function()
    boot({ noByTargetAtlases = true, saved = { targetIcon = "bytarget" } })
    setTarget({ isPlayer = false, reaction = 2 })
    eq(drawnLook(), "Interface\\Icons\\Ability_DualWield")
    setTarget({ isPlayer = false, reaction = 4 })
    eq(drawnLook(), "Interface\\Icons\\INV_Misc_QuestionMark")
    setTarget({ isPlayer = false, reaction = 5 })
    eq(drawnLook(), "Interface\\GossipFrame\\GossipGossipIcon")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 2, faction = "Alliance" })
    eq(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "no faction atlas: the reticle")
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
