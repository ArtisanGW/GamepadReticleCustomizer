-- GamepadReticleCustomizer against a fake game: the controller's reticle, frames
-- and textures, the Settings API, the color picker, a controller, addons installed
-- or not. From GamepadReticleCustomizer:  luajit tests/run.lua
local reportLine = print   -- the tests replace print to read what the addon says
local failed, passed = 0, 0
local only = os.getenv("GRC_TEST")   -- run only the tests whose name holds this
local function test(name, testBody)
    if only and not name:find(only, 1, true) then return end
    local ok, err = xpcall(testBody, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; reportLine("FAIL " .. name .. "\n" .. err) end
end
local function expectEqual(actual, expected, message)
    if actual ~= expected then error((message or "") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
local function near(actual, expected, message) if math.abs(actual - expected) > 0.01 then error((message or "") .. ": expected " .. expected .. ", got " .. actual, 2) end end
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
local function outlined(border) return border:GetWidth() + 2 * border.offset[1] end

local function newRegion(parent)
    local region = { parent = parent, shown = true, alpha = 1, width = 0, height = 0, color = { 1, 1, 1, 1 } }
    function region:SetPoint(_, relativeTo, _, x, y) self.relativeTo, self.offset = relativeTo, { x or 0, y or 0 } end
    function region:GetParent() return self.parent end
    -- As the game: anchored to a restricted region (a nameplate), it can't be measured.
    function region:GetPoint()
        if type(self.relativeTo) == "table" and self.relativeTo.restricted then
            error("GetPoint(): Action[FrameMeasurement] failed because[Can't measure restricted regions]")
        end
        if self.relativeTo then return "CENTER", self.relativeTo, "CENTER", (self.offset or {})[1] or 0, (self.offset or {})[2] or 0 end
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
        local coords = self.texCoord or { 0, 1, 0, 1 }   -- left, right, top, bottom as set
        return coords[1], coords[3], coords[1], coords[4], coords[2], coords[3], coords[2], coords[4]
    end
    function region:GetTexture() return self.texture end
    function region:SetColorTexture(red, green, blue, alpha) self.color = { red, green, blue, alpha } end
    function region:SetVertexColor(red, green, blue, alpha) self.color = { red, green, blue, alpha or 1 } end
    function region:SetDesaturated(desaturated) self.desaturated = desaturated end
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
    function region:IsForbidden() return self.forbidden == true end
    return region
end

-- A value the game hides from addons in instances (a secret value): comparing or
-- indexing it is an error, as in the game; issecretvalue tells it apart.
local secretMetatable = {}
local function secretUsed() error("attempt to use a secret value", 2) end
secretMetatable.__eq, secretMetatable.__lt, secretMetatable.__le, secretMetatable.__index = secretUsed, secretUsed, secretUsed, secretUsed
local function secretValue() return setmetatable({}, secretMetatable) end

local function boot(options)
    options = options or {}
    game = { frames = {}, settings = {}, callbacks = {}, controls = {}, time = 100, printed = {}, timers = {} }
    -- Action slots: game.actions[slot] = true (in range), false (out), "unknown" (can't tell).
    game.actions = {}
    _G.HasAction = function(slot) return game.actions[slot] ~= nil end
    _G.IsActionInRange = function(slot) local inRange = game.actions[slot]; if inRange == "unknown" then return nil end; return inRange end
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
    _G.C_Timer = { After = function(_, callback) game.timers[#game.timers + 1] = callback end }
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
    -- The game's atlases for kinds of target (none, with options.noKindAtlases).
    local kindAtlases = { ["UI-HUD-UnitFrame-Player-PVP-AllianceIcon"] = true, ["UI-HUD-UnitFrame-Player-PVP-HordeIcon"] = true,
        ["honorsystem-portrait-neutral"] = true, ["honorsystem-portrait-alliance"] = true,
        ["honorsystem-portrait-horde"] = true, ["UI-HUD-UnitFrame-Player-PVP-FFAIcon"] = true, ["pvptalents-warmode-swords"] = true, ["SideInProgressquesticon"] = true, ["Crosshair_Speak_128"] = true }
    _G.C_Texture = { GetAtlasInfo = function(atlas)
        if atlas:find("^classicon%-") and options.classAtlases ~= false then
            return { file = "classicons-file", leftTexCoord = 0.5, rightTexCoord = 0.75, topTexCoord = 0.25, bottomTexCoord = 0.5 }
        end
        if kindAtlases[atlas] and not options.noKindAtlases then
            return { file = atlas .. "-file", leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
        end
    end }
    -- The target's side, owner and tooltip title (game.target.faction, .controlled, .title).
    _G.UnitFactionGroup = function(unit)
        if unit == "player" then return "Horde" end
        return game.target and unit == "target" and game.target.faction or nil
    end
    _G.UnitPlayerControlled = function(unit) return game.target ~= nil and unit == "target" and (game.target.controlled or game.target.isPlayer) == true end
    -- The game's interaction icon for a unit (game.target.interaction: "buy", "train"...), put on a texture.
    _G.SetUnitCursorTexture = function(texture, unit, _, _, preferGamepadIcon)
        local interaction = game.target and unit == "target" and game.target.interaction
        if not interaction then return false end
        -- As the game: in range, asked for the controller's icon, its interact button instead.
        texture.cursorIcon = (preferGamepadIcon and game.target.inRange) and "gamepad-button" or interaction
        function texture:GetTexture() return "Cursor Crosshair_" .. self.cursorIcon .. "_64" end
        return true
    end
    game.classColors = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
        PRIEST = { r = 1, g = 1, b = 1 }, DRUID = { r = 1, g = 0.49, b = 0.04 } }
    _G.C_ClassColor = { GetClassColor = function(classFile) return game.classColors[classFile] end }
    -- The target's nameplate (unless target.nameplate == false: a vendor, a minion, or
    -- off screen), a player's health bar in its class's color (as the game shows them).
    -- Other units' nameplates: game.plates[unit] (Nearby's tests).
    game.plates = {}
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        if game.plates[unit] then return game.plates[unit] end
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
    _G.issecretvalue = function(value) return getmetatable(value) == secretMetatable end
    _G.canaccesstable = function(value) return value.forbidden ~= true end
    -- The game's settings (CVars): saved values (options.cvars, else the game's
    -- defaults) and temporary ones over them (options.tempCVars: the controller UI's).
    -- As measured in the game: SetCVar changes the saved value only, hidden under a
    -- temporary one. game.cvarsSet: each SetCVar, in order.
    game.cvars = options.cvars or { SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetIconGameObject = "0",
        nameplateGameObjectMaxDistance = "30" }
    game.tempCVars = options.tempCVars or {}
    game.cvarsSet = {}
    -- As the game: an addon can't change a secure one in a fight.
    local function refuseInFight(name)
        local secure = { SoftTargetInteract = true, nameplateGameObjectMaxDistance = true }
        if secure[name] and game.combat then error("ADDON_ACTION_BLOCKED SetCVar " .. name) end
    end
    _G.C_CVar = {
        GetCVar = function(name) return game.tempCVars[name] or game.cvars[name] end,
        SetCVar = function(name, value)
            refuseInFight(name)
            game.cvars[name] = value
            game.cvarsSet[#game.cvarsSet + 1] = name .. "=" .. value
            return true
        end,
        SetTempCVar = function(name, value) refuseInFight(name); game.tempCVars[name] = value end,
        RemoveTempCVar = function(name) refuseInFight(name); game.tempCVars[name] = nil end,
    }
    -- Units' tooltips (game.tooltips[unit]: the lines) and your quest log (game.quests:
    -- { questID, objectives = { { text, type, finished } } }).
    game.tooltips, game.quests = {}, {}
    _G.Enum = { TooltipDataLineType = { UnitName = 2, QuestObjective = 8, QuestTitle = 17 } }
    _G.C_TooltipInfo = { GetUnit = function(unit)
        local lines = game.tooltips[unit]
        if getmetatable(lines) == secretMetatable then return lines end
        return lines and { lines = lines } or nil
    end }
    _G.C_QuestLog = {
        GetNumQuestLogEntries = function() return #game.quests end,
        GetInfo = function(index) return game.quests[index] and { questID = game.quests[index].questID, isHeader = false } end,
        GetQuestObjectives = function(questID)
            for _, quest in ipairs(game.quests) do if quest.questID == questID then return quest.objectives end end
        end,
    }
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
        SetOnValueChangedCallback = function(variable, callback) game.callbacks[variable] = callback end,
        RegisterProxySetting = function(_, variable, _, label, _, getValue, setValue)
            local setting = { variable = variable, label = label, getValue = getValue, setValue = setValue }
            game.settings[variable] = setting
            return setting
        end,
        CreateCheckbox = function(_, setting, tooltip) addControl("checkbox", setting, { tooltip = tooltip }) end,
        CreateSlider = function(_, setting, sliderOptions, tooltip) sliderOptions.tooltip = tooltip; addControl("slider", setting, sliderOptions) end,
        CreateSliderOptions = function(minimum, maximum, step)
            return { minimum = minimum, maximum = maximum, step = step, SetLabelFormatter = function(self, _, formatter) self.format = formatter end }
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
        HookScript = function(_, script, hook) game.picker.hooks[script] = hook end,
        Show = function() game.picker.shown = true; if game.picker.hooks.OnShow then game.picker.hooks.OnShow() end end,
        Hide = function() game.picker.shown = false; if game.picker.hooks.OnHide then game.picker.hooks.OnHide() end end,
        Content = {
            ColorPicker = {
                GetColorHSV = function() return game.picker.hsv[1], game.picker.hsv[2], game.picker.hsv[3] end,
                SetColorHSV = function(_, hue, saturation, brightness) game.picker.hsv = { hue, saturation, brightness } end,
                GetColorAlpha = function() return game.picker.alpha end,
                SetColorAlpha = function(_, alpha) game.picker.alpha = alpha end,
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
    _G.print = function(text) game.printed[#game.printed + 1] = text end
    local namespace = {}
    for _, fileName in ipairs(tocFiles(options.releaseBuild)) do assert(loadfile(fileName))("GamepadReticleCustomizer", namespace) end
    fire("ADDON_LOADED", "GamepadReticleCustomizer")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD")
end
-- Changes the target as the game does: then PLAYER_TARGET_CHANGED.
local function setTarget(target) game.target = target; game.fire("PLAYER_TARGET_CHANGED") end
local function runNextFrame() local timers = game.timers; game.timers = {}; for _, timer in ipairs(timers) do timer() end end
local function runUntilNoTimersLeft()
    for _ = 1, 5000 do if #game.timers == 0 then return end; runNextFrame() end
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
    local lists = { icon = icons.ReticleList, friendlyClassStyle = icons.ClassStyleList, otherClassStyle = icons.ClassStyleList }
    local list = lists[key] and lists[key]() or icons.TargetList(key)   -- else a kind of target's choices
    setting(key .. "Choice"):SetValue(GamepadReticleCustomizer.ChoiceIndex(list, id))
end

-- The settings page

test("its page under Options > AddOns, in order, with the defaults; /gprc opens it", function()
    boot()
    expectEqual(game.category.name, "Gamepad Reticle Customizer")
    expectEqual(controlList(), "checkbox:Enable, slider:Size, swatch:Color, button:(Reset color), slider:Border, "
        .. "swatch:Border color, button:(Reset border color), "
        .. "slider:Icon size, slider:Horde players, slider:Alliance players, slider:Friendly NPCs, slider:Neutral NPCs, slider:Enemy NPCs, button:More looks, checkbox:Object icons, checkbox:Quest icons, button:Camera over shoulder, button:Reticle on your target, button:Map without its hitch",
        "without Jiberish Fabled Icons: no one-choice Reticle or Class icons slider; its button, More looks")
    boot({ jiberish = true })
    expectEqual(controlList(), "checkbox:Enable, slider:Reticle, slider:Size, swatch:Color, button:(Reset color), slider:Border, "
        .. "swatch:Border color, button:(Reset border color), "
        .. "slider:Icon size, slider:Horde players, slider:Horde class icons, slider:Alliance players, slider:Alliance class icons, "
        .. "slider:Friendly NPCs, slider:Neutral NPCs, slider:Enemy NPCs, checkbox:Object icons, checkbox:Quest icons, button:Camera over shoulder, button:Reticle on your target, button:Map without its hitch",
        "with it: the shapes, and each player row's class style right under it, always")
    boot()
    local saved = GamepadReticleCustomizerDB
    expectEqual(saved.enabled, true); expectEqual(saved.color, "FFFFFFFF"); expectEqual(saved.size, 4); expectEqual(saved.borderSize, 0)
    expectEqual(saved.borderColor, "000000FF"); expectEqual(saved.icon, "dot")
    for _, key in ipairs({ "friendlyPlayerIcon", "otherFactionIcon", "friendlyNpcIcon", "neutralNpcIcon", "enemyNpcIcon" }) do
        expectEqual(saved[key], "none", key .. ": nothing on a target by default")
    end
    expectEqual(saved.iconSize, 32)
    expectEqual(control("slider", "Size").extra.format(4), "4 (default)"); expectEqual(control("slider", "Size").extra.format(24), "24")
    expectEqual(control("slider", "Border").extra.format(0), "Off"); expectEqual(control("slider", "Border").extra.format(3), "3")
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("")
    expectEqual(game.opened, 42)
end)

-- Drawing

test("at login: our reticle drawn on the game's, the game's dot see-through, your settings on it", function()
    boot({ saved = { color = "C351B4E4", size = 10 } })
    expectEqual(layer().parent, GamepadReticle.Icons, "a child of the game's Icons: shows, hides and fades with it")
    expectEqual(layer().relativeTo, GamepadReticle.Icons.StandardIcon, "centered on the game's dot")
    expectEqual(layer():IsShown(), true)
    expectEqual(GamepadReticle.Icons.StandardIcon:GetAlpha(), 0, "the game's dot see-through, not hidden or changed")
    expectEqual(GamepadReticle.Icons.StandardIcon.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "its texture untouched")
    expectEqual(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "the game's dot shape")
    expectEqual(layer().shape:GetWidth(), 10)
    expectEqual(colorOf(layer().shape), string.format("%.2f %.2f %.2f %.2f", 0xC3 / 255, 0x51 / 255, 0xB4 / 255, 0xE4 / 255))
    expectEqual(layer().border:IsShown(), false, "no border by default")
end)

test("Enable off puts the game's dot back at its own alpha; on draws ours again", function()
    boot({ gameDotAlpha = 0.7 })
    setting("enabled"):SetValue(false)
    expectEqual(layer():IsShown(), false)
    expectEqual(GamepadReticle.Icons.StandardIcon:GetAlpha(), 0.7, "the alpha it had before we first drew")
    setting("enabled"):SetValue(true)
    expectEqual(layer():IsShown(), true); expectEqual(GamepadReticle.Icons.StandardIcon:GetAlpha(), 0)
end)

test("size and border: the slider values, clamped; border 0 hides it", function()
    boot()
    setting("size"):SetValue(24)
    expectEqual(layer().shape:GetWidth(), 24); expectEqual(layer().shape:GetHeight(), 24)
    setting("borderSize"):SetValue(3)
    expectEqual(layer().border:IsShown(), true)
    local copies = layer().border.outlineCopies
    expectEqual(#copies, 8, "an outline: 8 copies")
    expectEqual(layer().border:GetWidth(), layer().shape:GetWidth(), "each the shape's own size")
    expectEqual(table.concat(copies[1].offset, " "), "3 0", "shifted out by the border")
    expectEqual(table.concat(copies[4].offset, " "), "0 -3")
    expectEqual(copies[8].relativeTo, layer().shape, "around the shape")
    expectEqual(copies[8].texture, layer().shape.texture, "the same shape, behind it")
    expectEqual(colorOf(copies[8]), "0.00 0.00 0.00 1.00", "black by default")
    setting("borderSize"):SetValue(0)
    expectEqual(layer().border:IsShown(), false)
    expectEqual(copies[8]:IsShown(), false, "all of it")
    setting("size"):SetValue(500)
    expectEqual(layer().shape:GetWidth(), 64, "clamped to the slider's end")
    setting("size"):SetValue("nonsense")
    expectEqual(layer().shape:GetWidth(), 4, "not a number: the default")
end)

-- Colors

test("the color: 32 bits RRGGBBAA from /gprc, six digits opaque, a wrong one changes nothing", function()
    boot()
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("FF3030CC")
    expectEqual(GamepadReticleCustomizerDB.color, "FF3030CC")
    expectEqual(colorOf(layer().shape), "1.00 0.19 0.19 0.80", "drawn at once")
    expectEqual(game.printed[#game.printed]:find("FF3030CC", 1, true) ~= nil, true, "and says so")
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("nonsense")
    expectEqual(GamepadReticleCustomizerDB.color, "FF3030CC", "a wrong color changes nothing")
    expectEqual(game.printed[#game.printed]:find("usage", 1, true) ~= nil, true, "and says how")
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("#00ff00")
    expectEqual(GamepadReticleCustomizerDB.color, "00FF00FF", "six digits: opaque")
end)

test("the two swatches speak AARRGGBB, each for its own color; the opacity is kept", function()
    boot({ saved = { color = "00FF0066", borderSize = 2 } })
    local colorSwatch, borderSwatch = control("swatch", "Color").setting, control("swatch", "Border color").setting
    expectEqual(colorSwatch.getValue(), "FF00FF00", "alpha FF, the color")
    colorSwatch.setValue("ff0000ff")
    expectEqual(GamepadReticleCustomizerDB.color, "0000FF66", "the picked color, the opacity kept")
    colorSwatch.setValue("nonsense")
    expectEqual(GamepadReticleCustomizerDB.color, "0000FF66", "a wrong value changes nothing")
    borderSwatch.setValue("ffffffff")
    expectEqual(GamepadReticleCustomizerDB.borderColor, "FFFFFFFF", "the border's own color")
    expectEqual(GamepadReticleCustomizerDB.color, "0000FF66", "the reticle's untouched")
    expectEqual(colorOf(layer().border), "1.00 1.00 1.00 1.00", "drawn at once")
end)

test("the picker's opacity bar is for the color whose swatch opened it", function()
    boot({ saved = { color = "FFFFFF80", borderColor = "00000040", borderSize = 1 } })
    control("swatch", "Border color").setting.getValue()
    ColorPickerFrame:Show()
    near(game.picker.alpha, 0x40 / 255, "the border's opacity on the bar")
    ColorPickerFrame.Content.ColorPicker:SetColorAlpha(1); ColorPickerFrame.opacityFunc()
    expectEqual(GamepadReticleCustomizerDB.borderColor, "000000FF", "the bar sets the border's")
    expectEqual(GamepadReticleCustomizerDB.color, "FFFFFF80", "not the reticle's")
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
    expectEqual(driver.shown, false, "a picker opened by something else (the chat settings): left to the game")
    expectEqual(ColorPickerFrame.hasOpacity, nil, "and no opacity bar put on it")
    ColorPickerFrame:Hide()
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("FFFFFF80")
    control("swatch", "Color").setting.getValue()   -- the swatch reads the color as it opens the picker
    game.time = game.time + 0.1
    ColorPickerFrame:Show()
    expectEqual(driver.shown, true, "opened for the reticle color")
    expectEqual(ColorPickerFrame.hasOpacity, true, "the opacity bar put on the picker")
    near(game.picker.alpha, 128 / 255, "at the reticle's opacity")
    game.padUp = true; step(0.5)
    near(game.picker.alpha, 128 / 255 + 0.25, "D-pad up: more solid (0.5 a second)")
    expectEqual(GamepadReticleCustomizerDB.color:sub(7, 8), string.format("%02X", math.floor((128 / 255 + 0.25) * 255 + 0.5)),
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
    expectEqual(driver.shown, false, "picker shut: nothing runs")
end)

test("controller: the D-pad up/down icon under the opacity bar, pressed while held", function()
    boot()
    local driver = GamepadReticleCustomizer.PickerSticks.driver
    _G.InputIconTextureSetUtility = {
        GetActiveInputIconButtonTextures = function(key)
            if key == "DIRPADVERTICAL" then return { "dpadupdown-normal", "over", "dpadupdown-down", "focus", "disabled" } end
        end,
    }
    local icon
    ColorPickerFrame.CreateTexture = function()
        icon = { shown = false }
        function icon:SetAtlas(atlas) self.atlas = atlas end
        function icon:SetSize() end
        function icon:ClearAllPoints() end
        function icon:SetPoint(...) self.point = { ... } end
        function icon:Show() self.shown = true end
        function icon:Hide() self.shown = false end
        function icon:IsShown() return self.shown end
        return icon
    end
    control("swatch", "Color").setting.getValue()
    ColorPickerFrame:Show()
    expectEqual(icon.shown, true, "shown")
    expectEqual(icon.atlas, "dpadupdown-normal", "the game's art for the controller in use")
    expectEqual(icon.point[2], ColorPickerFrame.Content.ColorPicker.Alpha, "under the opacity bar")
    game.padUp = true; driver.scripts.OnUpdate(driver, 0.1)
    expectEqual(icon.atlas, "dpadupdown-down", "pressed while held")
    game.padUp = false; driver.scripts.OnUpdate(driver, 0.1)
    expectEqual(icon.atlas, "dpadupdown-normal", "back when let go")
    ColorPickerFrame:Hide()
    expectEqual(icon.shown, false, "hidden with the picker")
    _G.InputIconTextureSetUtility, ColorPickerFrame.CreateTexture = nil, nil
end)

test("keyboard: the picker gets the opacity bar but no stick driver", function()
    boot({ keyboard = true })
    control("swatch", "Color").setting.getValue()
    ColorPickerFrame:Show()
    expectEqual(ColorPickerFrame.hasOpacity, true)
    expectEqual(GamepadReticleCustomizer.PickerSticks.driver.shown, false)
end)

-- Shapes

test("the reticle: the game's dot, no Jiberish shapes without it; a Jiberish id without it falls back to the dot", function()
    boot()
    expectEqual(control("slider", "Reticle"), nil, "one choice only: no slider")
    GamepadReticleCustomizerDB.icon = "jiberish:x-bold"; GamepadReticleCustomizer.UpdateReticle()
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot")
end)

test("with Jiberish Fabled Icons installed: its 16 reticles listed and drawn from its folder, credited, no install button", function()
    boot({ jiberish = true })
    local labels = choiceLabels("Reticle")
    expectEqual(#labels, 17, "the dot and 16 Jiberish shapes")
    expectEqual(labels[2], "Circle (bold)"); expectEqual(labels[8], "Split plus (bold)"); expectEqual(labels[17], "X (thin)")
    choose("icon", "jiberish:splitplus-thin")
    expectEqual(GamepadReticleCustomizerDB.icon, "jiberish:splitplus-thin", "the slider's step saved as the shape's id")
    expectEqual(layer().shape.texture, "Interface\\AddOns\\JiberishIcons\\Media\\Crosshair\\splitplus-thin-128")
    expectEqual(control("button", "More looks"), nil, "no install button when it's there")
    expectEqual(control("slider", "Reticle").extra.tooltip:find("Shapes from Jiberish Fabled Icons", 1, true) ~= nil, true,
        "credited, as its license asks")
end)

test("choices are sliders (a dropdown's menu breaks on the controller): each kind of target, None, its own icon, the 8 raid markers, then the game's icons", function()
    boot()
    local labels = choiceLabels("Horde players")
    expectEqual(#labels, 3 + 8 + 12)
    expectEqual(labels[1], "None"); expectEqual(labels[2], "Faction"); expectEqual(labels[3], "Class")
    expectEqual(labels[11], "Raid marker: Skull"); expectEqual(labels[12], "Icon: Sniper scope"); expectEqual(labels[23], "Icon: Holy")
    expectEqual(table.concat(choiceLabels("Alliance players"), ","):sub(1, 18), "None,Faction,Class")
    expectEqual(choiceLabels("Friendly NPCs")[2], "Their job"); expectEqual(choiceLabels("Neutral NPCs")[2], "Gray dots")
    expectEqual(choiceLabels("Enemy NPCs")[2], "Sword")
    choose("enemyNpcIcon", "marker8")
    expectEqual(GamepadReticleCustomizerDB.enemyNpcIcon, "marker8")
    setTarget({ isPlayer = false, reaction = 2 })
    choose("enemyNpcIcon", "icon:scope")
    expectEqual(layer().shape.texture, "Interface\\Icons\\Ability_Hunter_SniperShot", "a game icon on the target")
    setTarget({ isPlayer = false, reaction = 5 })
    expectEqual(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "another kind, still None: the reticle")

    boot({ saved = { friendlyPlayerIcon = "class", icon = "dot" } })
    expectEqual(GamepadReticleCustomizer.choices.friendlyPlayerIcon, 3, "the slider starts at your saved choice")
end)

test("icons show only while you have a target, at the icon size, in their own colors; the reticle comes back", function()
    boot({ saved = { color = "FF3030FF", size = 6, targetIcon = "marker8", iconSize = 30, borderSize = 2 } })
    expectEqual(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "no target: the reticle")
    expectEqual(layer().shape:GetWidth(), 6); expectEqual(colorOf(layer().shape), "1.00 0.19 0.19 1.00")
    setTarget({ isPlayer = false, reaction = 2 })
    expectEqual(layer().shape.texture, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", "a target: the skull")
    expectEqual(layer().shape:GetWidth(), 30, "at the icon size")
    expectEqual(colorOf(layer().shape), "1.00 1.00 1.00 1.00", "in its own colors")
    expectEqual(layer().border:GetWidth(), 30, "the border: an outline, copies at its size")
    expectEqual(layer().border.offset[1], 2, "shifted out by the border")
    expectEqual(layer().shape.texCoord[2], 1, "shown whole")
    setTarget(nil)
    expectEqual(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "target gone: the reticle back")
    expectEqual(layer().shape:GetWidth(), 6); expectEqual(colorOf(layer().shape), "1.00 0.19 0.19 1.00")
end)

test("a player's class icon: the game's classicon atlas for players; NPCs, an unknown class or a missing atlas keep the reticle", function()
    boot({ saved = { targetIcon = "class" } })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-mage")
    expectEqual(layer().shape.texture, "classicons-file", "drawn as the atlas's file")
    expectEqual(table.concat(layer().shape.texCoord, ","), "0.5,0.75,0.25,0.5", "and its cell")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "class")
    expectEqual(layer().shape:GetWidth(), 32)
    setTarget({ isPlayer = true, classFile = "DRUID", reaction = 2 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-druid", "an enemy player too")
    setTarget({ isPlayer = false, reaction = 4 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "an NPC: the reticle")
    expectEqual(layer().shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "the dot's texture")
    expectEqual(table.concat(layer().shape.texCoord, ","), "0,1,0,1", "shown whole again")
    setTarget({ isPlayer = true, classFile = nil, reaction = 5 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "class unknown (hidden): the reticle")
    boot({ saved = { targetIcon = "class" }, classAtlases = false })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "no such atlas on this client: the reticle")
end)

test("a target without a nameplate on screen (a vendor, a minion, off screen) keeps the reticle; its nameplate coming brings the icon", function()
    boot({ saved = { targetIcon = "marker8", iconSize = 30 } })
    setTarget({ isPlayer = false, reaction = 5, nameplate = false, plateUnit = "nameplate4" })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "a vendor with friendly NPC nameplates off: the reticle")
    game.target.nameplate = true
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "marker8", "its nameplate shows: the icon")
    game.target.nameplate = false
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "marker8", "another unit's nameplate: nothing redrawn")
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate4")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "the target off screen: the reticle back")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5, nameplate = false })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "a player with friendly nameplates off: the reticle")
end)

test("a client without an atlas file: SetAtlas, after resetting the cell a Jiberish style left", function()
    boot({ jiberish = true, saved = { targetIcon = "class", classStyle = "jiberish:fabled" } })
    _G.C_Texture.GetAtlasInfo = function(atlas) if atlas:find("^classicon%-") then return {} end end
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 5 })
    expectEqual(table.concat(layer().shape.texCoord, ","), "0.25,0.375,0.125,0.25", "the Jiberish cell")
    choose("friendlyClassStyle", "game")
    expectEqual(layer().shape.atlas, "classicon-priest")
    expectEqual(table.concat(layer().shape.texCoord, ","), "0,1,0,1", "reset before SetAtlas")
end)

-- Every kind of target's choice, in TARGET_KINDS' order.
local function kindChoices()
    local saved, choices = GamepadReticleCustomizerDB, {}
    for _, kind in ipairs(GamepadReticleCustomizer.TARGET_KINDS) do choices[#choices + 1] = saved[kind.key] end
    return table.concat(choices, " ")
end

test("saved settings in older forms: a marker in the shape, one choice for every target, a custom texture", function()
    boot({ saved = { icon = "marker2" } })
    expectEqual(GamepadReticleCustomizerDB.icon, "dot"); expectEqual(kindChoices(), "marker2 marker2 marker2 marker2 marker2", "on every kind")
    expectEqual(GamepadReticleCustomizerDB.targetIcon, nil)
    boot({ saved = { targetIcon = "class" } })
    expectEqual(kindChoices(), "class class none none none", "a class: on players only")
    boot({ saved = { targetIcon = "custom", customTexture = "Interface\\Icons\\INV_Misc_QuestionMark" } })
    expectEqual(kindChoices(), "none none none none none", "no texture paths"); expectEqual(GamepadReticleCustomizerDB.customTexture, nil)
    boot({ saved = { icon = "custom", customTexture = 136243 } })
    expectEqual(kindChoices(), "none none none none none"); expectEqual(GamepadReticleCustomizerDB.icon, "dot")
    boot({ saved = { icon = "jiberish:x-bold" } })
    expectEqual(GamepadReticleCustomizerDB.icon, "jiberish:x-bold", "a reticle shape stays"); expectEqual(kindChoices(), "none none none none none")
end)

test("Jiberish Fabled Icons installed but turned off: not offered, its choices fall back, a button tells how to turn it on", function()
    boot({ jiberishOff = true, saved = { icon = "jiberish:x-bold", size = 24, targetIcon = "class", classStyle = "jiberish:fabled" } })
    expectEqual(control("slider", "Reticle"), nil, "its shapes aren't offered")
    expectEqual(control("slider", "Horde class icons"), nil, "nor its styles")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "a saved Jiberish shape falls back to the dot")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-mage", "and a Jiberish class style to the game's")
    expectEqual(GamepadReticleCustomizerDB.icon, "jiberish:x-bold", "your choice kept for when it's on again")
    local button = control("button", "More looks")
    expectEqual(button.extra.buttonText, "Enable Jiberish Fabled Icons", "not Get: it's installed")
    button.extra.onClick()
    expectEqual(popup():IsShown(), true, "the game-style popup")
    expectEqual(popup().Border.template, "DialogBorderTemplate", "the game's dialog border")
    expectEqual(popup().text.text:find("turned off", 1, true) ~= nil, true, popup().text.text)
    expectEqual(popup().editBox:IsShown(), false, "a message: nothing to copy")
    expectEqual(popupButtons(), "Not now, [secure] Turn on and reload")
    clickPopupButton("Turn on and reload")
    expectEqual(game.enabledAddOn.name, "JiberishIcons", "turned on")
    expectEqual(game.enabledAddOn.character, "Player-93-0A1B2C3D", "for this character, by its GUID as the AddOns list does (not its name)")
    expectEqual(game.enabledAddOn.saved, true, "saved before the reload, as the AddOns list does (or it stays off)")
    expectEqual(game.reloaded, "/reload", "then reloaded by the secure button")
end)

test("without it: the install button shows the link to copy", function()
    boot()
    expectEqual(control("button", "More looks").extra.buttonText, "Get Jiberish Fabled Icons", "in the Class icons row")
    control("button", "More looks").extra.onClick()
    expectEqual(popup():IsShown(), true)
    expectEqual(popup().editBox:GetText(), "https://www.curseforge.com/wow/addons/jiberish-fabled-icons")
    expectEqual(popup().editBox.highlighted, true, "selected, ready for Ctrl+C")
    expectEqual(popupButtons(), "Close, [secure] Reload", "a Reload for once it's installed")
    clickPopupButton("Close")
    expectEqual(popup():IsShown(), false)
end)

test("no icon picker and no texture paths: no Choose icon button, /gprc texture is just a wrong color", function()
    boot()
    expectEqual(control("button", "Choose icon"), nil)
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("texture Interface\\Icons\\Spell_Nature_Starfall")
    expectEqual(game.printed[#game.printed]:find("usage: /gprc RRGGBBAA", 1, true) ~= nil, true, game.printed[#game.printed])
    expectEqual(GamepadReticleCustomizer.IconPicker, nil)
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
                        expectEqual(afterColon, nil, name .. ": \"" .. line .. "\"")
                    end
                end
                expectEqual(tooltip:find("preview shows", 1, true), nil, name .. ": no telling what the preview shows")
            end
        end
    end
end)

test("every choice slider's label fits the slider (22 characters, seen cut in game beyond)", function()
    boot({ jiberish = true })
    local maxLength = GamepadReticleCustomizer.Icons.LABEL_MAX_LENGTH
    for _, slider in ipairs({ "Reticle", "Horde players", "Alliance players", "Friendly NPCs", "Neutral NPCs", "Enemy NPCs", "Horde class icons" }) do
        for _, label in ipairs(choiceLabels(slider)) do
            expectEqual(#label <= maxLength, true, slider .. ": \"" .. label .. "\" is " .. #label .. " characters")
        end
    end
end)

test("the dot and the shapes keep their own sizes: a shape starts at 32, the dot gets its own back", function()
    boot({ jiberish = true, saved = { size = 6 } })
    choose("icon", "jiberish:x-bold")
    expectEqual(GamepadReticleCustomizerDB.size, 32, "a shape starts at 32: at the dot's size it can't be seen")
    setting("size"):SetValue(40)
    choose("icon", "jiberish:plus-thin")
    expectEqual(GamepadReticleCustomizerDB.size, 40, "shape to shape: the size kept")
    choose("icon", "dot")
    expectEqual(GamepadReticleCustomizerDB.size, 6, "back to the dot: the dot's own size, not 24 or 40")
    expectEqual(layer().shape:GetWidth(), 6)
    choose("icon", "jiberish:x-thin")
    expectEqual(GamepadReticleCustomizerDB.size, 40, "back to a shape: the shapes' size")
end)

test("the reset rows' label is one space: blank, yet not \"\", so the game lines the button up with the others", function()
    boot()
    expectEqual(control("button", "Reset color").extra.name, " ")
    expectEqual(control("button", "Reset border color").extra.name, " ")
end)

test("each color has its own reset: the reticle's to white, the border's to black", function()
    boot({ saved = { color = "FF3030CC", borderColor = "00FF00FF", borderSize = 2 } })
    control("button", "Reset color").extra.onClick()
    expectEqual(GamepadReticleCustomizerDB.color, "FFFFFFFF"); expectEqual(colorOf(layer().shape), "1.00 1.00 1.00 1.00")
    expectEqual(GamepadReticleCustomizerDB.borderColor, "00FF00FF", "the border's untouched")
    control("button", "Reset border color").extra.onClick()
    expectEqual(GamepadReticleCustomizerDB.borderColor, "000000FF"); expectEqual(colorOf(layer().border), "0.00 0.00 0.00 1.00")
end)

test("class icon styles: the game's, or a Jiberish Fabled Icons class sheet's cell for the class; without it, the game's", function()
    boot()
    expectEqual(control("slider", "Horde class icons"), nil, "without Jiberish Fabled Icons: no slider, the game's icons only")
    boot({ jiberish = true, saved = { targetIcon = "class" } })
    local labels = choiceLabels("Horde class icons")
    expectEqual(#labels, 12, "the game's and 11 Jiberish styles")
    expectEqual(labels[2], "Fabled"); expectEqual(labels[3], "Fabled Class"); expectEqual(labels[4], "Fabled Pixels")
    choose("friendlyClassStyle", "jiberish:fabledpixels")
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 5 })
    expectEqual(layer().shape.texture, "Interface\\AddOns\\JiberishIcons\\Media\\Class\\fabledpixels")
    expectEqual(table.concat(layer().shape.texCoord, ","), "0.25,0.375,0.125,0.25", "the Priest's cell: column 3, row 2 of 8")
    setTarget({ isPlayer = true, classFile = "DEMONHUNTER", reaction = 2 })
    expectEqual(table.concat(layer().shape.texCoord, ","), "0.375,0.5,0.25,0.375")
    choose("friendlyClassStyle", "game")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-demonhunter", "the game's again")
    expectEqual(layer().shape.texture, "classicons-file")
    expectEqual(table.concat(layer().shape.texCoord, ","), "0.5,0.75,0.25,0.5",
        "the game's cell, not the Jiberish one left behind (seen in game)")
    boot({ saved = { targetIcon = "class", classStyle = "jiberish:fabled" } })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().atlas, "classicon-mage", "a Jiberish style without the addon: the game's icon")
end)

test("without Gamepad Reticle On Target: a button shows its link to copy; with it, no button", function()
    boot()
    control("button", "Reticle on your target").extra.onClick()
    expectEqual(control("button", "Reticle on your target").extra.buttonText, "Get the addon")
    expectEqual(popup().editBox:GetText(), "https://www.curseforge.com/projects/1819101")
    expectEqual(popup().editBox.highlighted, true, "selected, ready for Ctrl+C")
    expectEqual(popupButtons(), "Close, [secure] Reload")
    boot({ reticleOnTargetInstalled = true })
    expectEqual(control("button", "Reticle on your target"), nil, "installed: no button")
end)

test("on the controller: A clicks the popup's first button, B the last, a hint says so; closing gives them back", function()
    boot()
    control("button", "More looks").extra.onClick()   -- Get Jiberish Fabled Icons: Reload, Close
    expectEqual(game.bindings.PAD1, "GamepadReticleCustomizerPopupReload", "A: the first button, Reload")
    expectEqual(game.bindings.PAD2, "GamepadReticleCustomizerPopupButton1", "B: the last, Close")
    expectEqual(popup().reloadButton.controllerIcon.atlas, "gamepad-test-pad1", "the A icon on Reload, as the game marks its buttons")
    expectEqual(popup().buttons[1].controllerIcon.atlas, "gamepad-test-pad2", "the B icon on Close")
    expectEqual(popup().hint.text, "", "the icons say it: no hint line")
    _G[game.bindings.PAD2]:Click()
    expectEqual(popup():IsShown(), false, "B closed it")
    expectEqual(game.bindings.PAD1, nil, "the controller's buttons given back"); expectEqual(game.bindings.PAD2, nil)
    expectEqual(game.bindings["ALT-CTRL-SHIFT-C"] ~= nil, true, "other bindings untouched")

    boot({ noControllerIcons = true })
    control("button", "More looks").extra.onClick()
    expectEqual(popup().hint.text, "A: Reload      B: Close", "no icons on this client: said in words")

    boot({ keyboard = true })
    control("button", "More looks").extra.onClick()
    expectEqual(game.bindings.PAD1, nil, "keyboard: no controller bindings"); expectEqual(popup().hint.text, "")
    expectEqual(popup().reloadButton.controllerIcon:IsShown(), false, "and no icons")
end)

test("in a fight, a popup (it holds a secure Reload) opens once the fight is over", function()
    boot()
    game.combat = true
    expectEqual(GamepadReticleCustomizer.Popup.Show({ text = "Hello", buttons = { { text = "Reload", reload = true } } }), false)
    expectEqual(popup(), nil, "not built in combat")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    expectEqual(popup():IsShown(), true, "after the fight")
    expectEqual(popup().text.text, "Hello")
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
    expectEqual(preview.parent, SettingsPanel, "on the settings window")
    expectEqual(preview.Bg.template, "FlatPanelBackgroundTemplate", "the settings window's own background")
    expectEqual(preview.NineSlice.template, "NineSlicePanelTemplate"); expectEqual(preview.NineSlice.layoutName, "ButtonFrameTemplateNoPortrait",
        "and its metal border")
    expectEqual(preview.reticle.template, "InsetFrameTemplate", "each cell an inset, as inside the game's windows")
    expectEqual(preview.title.text, "Preview")
    expectEqual(preview:IsShown(), false, "hidden until the page opens")
    showPage({ name = "Another page" })
    expectEqual(preview:IsShown(), false, "another page: hidden")
    showPage(game.category)
    expectEqual(preview:IsShown(), true, "our page: shown")
    local width, height = preview:GetWidth(), preview:GetHeight()
    expectEqual(preview.reticle.shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    -- Zoomed: the reticle and its border fill 80% of the 120 cell (96): 10 + 2 x 2 = 14 wide becomes 96.
    near(preview.reticle.shape:GetWidth(), 96 * 10 / 14, "zoomed to fill the cell")
    near(preview.reticle.border.offset[1], 2 * 96 / 14, "the outline zoomed too")
    expectEqual(colorOf(preview.reticle.shape), "1.00 0.19 0.19 1.00")
    expectEqual(preview.reticle.realShape:GetWidth(), 10, "and at its real size in the corner")
    expectEqual(preview.reticle.realBorder:GetWidth(), 10)
    expectEqual(preview.onTarget.shape.texture, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    near(outlined(preview.onTarget.border), 96, "an icon zoomed the same")
    near(outlined(preview.onTarget.realBorder), 32, "an icon bigger than the corner: shrunk to fit it (40 x 80%)")
    setting("size"):SetValue(20)
    expectEqual(preview.reticle.realShape:GetWidth(), 20, "redrawn on a change")
    near(outlined(preview.reticle.border), 96, "the zoomed view still fills the cell")
    expectEqual(preview:GetWidth(), width); expectEqual(preview:GetHeight(), height, "the window keeps its size")
    choose("friendlyPlayerIcon", "class")
    expectEqual(preview.onTarget.shape.texture, "classicons-file", "a player's class: your own as the example")
    choose("friendlyPlayerIcon", "none")
    expectEqual(preview.onTarget.label.text, "On a target: the reticle stays")
    expectEqual(preview.onTarget.shape.texture, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    setting("enabled"):SetValue(false)
    expectEqual(preview.alpha, 0.5, "the addon off: dimmed")
    showPage(nil)
    expectEqual(preview:IsShown(), false, "the window closed: hidden")
end)

-- /gprc debug, run here against the fake game

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
        runNextFrame()
    end
    error("the debug run never ended")
end

local function checkResult(run, wanted)
    for _, check in ipairs(run.checks) do
        if check.name:find(wanted, 1, true) then return check.result end
    end
end

test("/gprc debug: every look checked, on 3 friendly classes and both NPC kinds, your settings back, the reload box", function()
    for _, jiberish in ipairs({ false, true }) do
        boot({ jiberish = jiberish, saved = { color = "3961CDFF", size = 7, targetIcon = "marker2" } })
        SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
        local debugSuite = GamepadReticleCustomizer.Debug
        driveDebugRun({ { isPlayer = true, classFile = "WARRIOR", reaction = 5 }, { isPlayer = true, classFile = "WARRIOR", reaction = 5 },
            { isPlayer = true, classFile = "MAGE", reaction = 5 }, { isPlayer = true, classFile = "PRIEST", reaction = 5 } },
            { { isPlayer = false, reaction = 2 }, { isPlayer = false, reaction = 4 } })
        local run = GamepadReticleCustomizerDebugDB.runs[1]
        expectEqual(failedChecks(run), "", "no failed check (Jiberish " .. tostring(jiberish) .. ")")
        expectEqual(run.failed, 0)
        expectEqual(run.found.class1, "WARRIOR"); expectEqual(run.found.class2, "MAGE", "the second Warrior skipped: a class already seen")
        expectEqual(run.found.class3, "PRIEST"); expectEqual(run.found.class4, nil, "no fourth class near")
        expectEqual(run.found.npc1, "enemy"); expectEqual(run.found.npc2, "neutral", "both kinds")
        expectEqual(checkResult(run, "friendly player 2: its class icon, size 32 (MAGE): its nameplate shows the class's color"), "pass")
        expectEqual(checkResult(run, "(within 60 s)"), "pass")
        expectEqual(run.passed > 150, true, "passed " .. run.passed)
        expectEqual(run.steps[3].onScreen.x, 1200, "where the reticle is, in screen pixels")
        expectEqual(debugSuite.marker:IsShown(), false, "the square gone: done")
        expectEqual(GamepadReticleCustomizerDB.color, "3961CDFF", "your settings back")
        expectEqual(GamepadReticleCustomizerDB.size, 7); expectEqual(GamepadReticleCustomizerDB.enemyNpcIcon, "marker2")
        expectEqual(GamepadReticleCustomizerDebugDB.settingsToRestore, nil)
        expectEqual(popup():IsShown(), true, "the reload popup")
        expectEqual(popupButtons(), "Later, [secure] Reload")
    end
end)

test("/gprc debug: alone (yourself, one NPC kind, no nameplates: the reticle stays), the optional parts are skipped, nothing fails", function()
    boot({ noNameplates = true })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    driveDebugRun({ { isPlayer = true, classFile = "DRUID", reaction = 5 } }, { { isPlayer = false, reaction = 4 } })
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    expectEqual(failedChecks(run), "", "nothing failed")
    expectEqual(run.found.class2, nil); expectEqual(run.found.npc1, "neutral"); expectEqual(run.found.npc2, nil)
    expectEqual(checkResult(run, "its nameplate shows the class's color"), nil, "no nameplate: no class icon, nothing to compare")
    expectEqual(checkResult(run, "target: its class icon, size 32 (DRUID): what's drawn"), "pass", "checked as the reticle staying")
    expectEqual(checkResult(run, "the other kind of NPC"), "skip")
end)

test("/gprc debug: an offered game icon missing on the client fails its check", function()
    boot()
    table.insert(GamepadReticleCustomizer.Icons.GAME_ICONS, { key = "gone", name = "Gone", file = "Interface\\Icons\\missing_icon" })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    driveDebugRun({ { isPlayer = true, classFile = "MAGE", reaction = 5 } }, { { isPlayer = false, reaction = 2 } })
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    expectEqual(checkResult(run, "every game icon offered exists on this client"), "fail")
    table.remove(GamepadReticleCustomizer.Icons.GAME_ICONS)
end)

test("/gprc friendly runs only the friendly player part, then the target cleared", function()
    boot({ saved = { color = "3961CDFF" } })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("friendly")
    driveDebugRun({ { isPlayer = true, classFile = "WARRIOR", reaction = 5 }, { isPlayer = true, classFile = "MAGE", reaction = 5 } },
        { { isPlayer = false, reaction = 2 } })
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    expectEqual(run.name, "friendly")
    expectEqual(failedChecks(run), "", "nothing failed")
    expectEqual(run.found.class1, "WARRIOR"); expectEqual(run.found.class2, "MAGE")
    expectEqual(run.found.npc1, nil, "no NPC part")
    expectEqual(checkResult(run, "dot, size 12, red"), nil, "no reticle-only part")
    expectEqual(checkResult(run, "target cleared: the reticle back"), "pass", "ends with the target cleared")
    expectEqual(GamepadReticleCustomizerDB.color, "3961CDFF", "your settings back")
    expectEqual(popup():IsShown(), true, "the reload popup")
end)

test("/gprc monsters runs only the NPC part, then the target cleared", function()
    boot()
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("monsters")
    driveDebugRun({ { isPlayer = true, classFile = "WARRIOR", reaction = 5 } },
        { { isPlayer = false, reaction = 4 }, { isPlayer = false, reaction = 1 } })
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    expectEqual(run.name, "monsters")
    expectEqual(failedChecks(run), "", "nothing failed")
    expectEqual(run.found.npc1, "neutral"); expectEqual(run.found.npc2, "enemy")
    expectEqual(run.found.class1, nil, "no friendly part")
    expectEqual(checkResult(run, "target cleared: the reticle back"), "pass")
end)

test("in the release (no Debug.lua), /gprc friendly and /gprc monsters open the settings", function()
    boot({ releaseBuild = true })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("friendly")
    expectEqual(game.opened, 42)
    game.opened = nil
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("monsters")
    expectEqual(game.opened, 42)
end)

test("/gprc debug: no friendly player selected within 60 s fails; its keys are bound", function()
    boot()
    expectEqual(game.bindings["ALT-CTRL-SHIFT-Y"], "GamepadReticleCustomizerDebugTarget")
    expectEqual(game.bindings["ALT-CTRL-SHIFT-Z"], "GamepadReticleCustomizerDebugTargetEnemy")
    expectEqual(game.bindings["ALT-CTRL-SHIFT-X"], "GamepadReticleCustomizerDebugClearTarget")
    expectEqual(GamepadReticleCustomizerDebugTarget.attributes.macrotext, "/targetfriendplayer\n/target [noexists] player")
    expectEqual(GamepadReticleCustomizerDebugTargetEnemy.attributes.macrotext, "/targetenemy")
    expectEqual(GamepadReticleCustomizerDebugClearTarget.attributes.macrotext, "/cleartarget")
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    driveDebugRun({}, {})
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    expectEqual(checkResult(run, "select a friendly player (within 60 s)"), "fail")
end)

test("/gprc debug: waits for the reticle on screen before its first step (the cursor hides it)", function()
    boot()
    GamepadReticle.Icons:Hide()   -- the cursor shows, as just after a reload
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    local debugSuite = GamepadReticleCustomizer.Debug
    expectEqual(colorOf(debugSuite.marker.texture), "1.00 1.00 0.00 1.00", "yellow: waiting")
    runNextFrame(); runNextFrame(); runNextFrame()
    expectEqual(colorOf(debugSuite.marker.texture), "1.00 1.00 0.00 1.00", "still waiting, no step yet")
    GamepadReticle.Icons:Show()
    runNextFrame(); runNextFrame()
    expectEqual(math.floor(debugSuite.marker.texture.color[3] * 255 + 0.5), 16,
        "once it shows: step 2 (step 1, waiting for no target, passed at once)")
    runUntilNoTimersLeft()
    local run = GamepadReticleCustomizerDebugDB.runs[1]
    expectEqual(run.environment.reticleWaitSeconds, 2, "waited 2 s (4 polls)")
    expectEqual(run.environment.reticleOnScreenAtStart, true)

    boot()
    GamepadReticleCustomizer.Debug.WAIT_SECONDS = 1
    GamepadReticle.Icons:Hide()
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    runUntilNoTimersLeft()
    expectEqual(GamepadReticleCustomizerDebugDB.runs[1].environment.reticleOnScreenAtStart, false, "never showed: runs anyway, says so")
end)

test("/gprc debug: Alt+Ctrl+Shift+C starts it too (for the screenshot script)", function()
    boot()
    expectEqual(game.bindings["ALT-CTRL-SHIFT-C"], "GamepadReticleCustomizerDebugStart")
    _G[game.bindings["ALT-CTRL-SHIFT-C"]]:Click()
    expectEqual(#game.timers > 0, true, "running")
    driveDebugRun({ { isPlayer = true, classFile = "MAGE", reaction = 5 } }, { { isPlayer = false, reaction = 2 } })
    expectEqual(GamepadReticleCustomizerDebugDB.runs[1].failed, 0)
end)

test("/gprc debug: a fight stops it, your settings back, the square red", function()
    boot({ saved = { color = "3961CDFF" } })
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    runNextFrame(); runNextFrame()
    game.combat = true
    game.fire("PLAYER_REGEN_DISABLED")
    expectEqual(GamepadReticleCustomizerDebugDB.runs[1].stopped, "combat")
    expectEqual(GamepadReticleCustomizerDB.color, "3961CDFF")
    expectEqual(GamepadReticleCustomizer.Debug.marker.texture.color[1], 1, "red")
    runUntilNoTimersLeft()
    expectEqual(#GamepadReticleCustomizerDebugDB.runs, 1, "nothing ran after the stop")
end)

test("/gprc debug: a reload in the middle of a run puts your settings back at the next login", function()
    boot({ saved = { color = "FF0000FF", size = 48 },
        debugSaved = { runs = {}, settingsToRestore = { color = "3961CDFF", size = 7, enabled = true } } })
    expectEqual(GamepadReticleCustomizerDB.color, "3961CDFF"); expectEqual(GamepadReticleCustomizerDB.size, 7)
    expectEqual(GamepadReticleCustomizerDebugDB.settingsToRestore, nil)
    expectEqual(layer().shape:GetWidth(), 7, "and drawn")
end)

-- The addon and its release

test("an addon of its own: needs no other addon; listed under Gamepad", function()
    local toc = readFile("GamepadReticleCustomizer.toc")
    expectEqual(toc:find("Dependencies", 1, true), nil); expectEqual(toc:find("OptionalDeps", 1, true), nil)
    expectEqual(toc:match("## Category: ([^\r\n]+)"), "Gamepad", "under Gamepad in the AddOns list, the game's own word")
end)

test("the release leaves Debug.lua out: ignored by .pkgmeta, and gone from the release .toc", function()
    assert(readFile(".pkgmeta"):find("\n  %- Code/Debug%.lua\n"), ".pkgmeta ignores Debug.lua, alone on its line")
    expectEqual(table.concat(tocFiles(true), ","),
        "Code/SavedSettings.lua,Code/Color.lua,Code/Icons.lua,Code/Target.lua,Code/Range.lua,Code/ObjectIcons.lua,Code/QuestIcons.lua,Code/Reticle.lua,Code/PickerSticks.lua,Code/Popup.lua,Code/Preview.lua,Code/RelatedAddons.lua,Code/GamepadReticleCustomizer.lua")
    expectEqual(tocFiles()[#tocFiles()], "Code/Debug.lua", "the repo's .toc loads it last")
end)

test("without Debug.lua (the release), the addon works and /gprc debug opens the settings", function()
    boot({ releaseBuild = true })
    expectEqual(GamepadReticleCustomizer.Debug, nil)
    expectEqual(layer():IsShown(), true)
    SlashCmdList.GAMEPADRETICLECUSTOMIZER("debug")
    expectEqual(game.opened, 42)
end)

test("the reticle left in the middle of the screen (nothing moves it): no icon, the reticle stays", function()
    boot({ reticleOnTarget = false, saved = { targetIcon = "marker8" } })
    game.fire("PLAYER_ENTERING_WORLD")
    setTarget({ isPlayer = false, reaction = 2, plateUnit = "nameplate4" })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "a target with its nameplate, but the reticle in the middle")
    expectEqual(GamepadReticleCustomizer.TargetInfo().reticleOnNameplate, false)
    -- Then something puts it under the nameplate (a restricted region: not measurable).
    GamepadReticle:SetPoint("CENTER", { restricted = true }, "BOTTOM")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "marker8", "redrawn as soon as it's moved there")
    GamepadReticle:SetPoint("CENTER", UIParent, "BOTTOM")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "and back in the middle: the reticle")
end)

test("the reticle on a nameplate that can be measured: the target's own counts, another frame doesn't", function()
    boot({ reticleOnTarget = false, saved = { targetIcon = "marker8" } })
    game.fire("PLAYER_ENTERING_WORLD")
    setTarget({ isPlayer = false, reaction = 2 })
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local healthBar = { GetParent = function() return plate end }
    C_NamePlate.GetNamePlateForUnit = function() return plate end
    GamepadReticle:SetPoint("CENTER", healthBar, "BOTTOM")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "marker8", "under a part of the target's nameplate")
    GamepadReticle:SetPoint("CENTER", { GetParent = function() return UIParent end }, "BOTTOM")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "under some other frame")
end)

test("/gprc and /gamepadreticlecustomizer", function()
    boot()
    expectEqual(SLASH_GAMEPADRETICLECUSTOMIZER1, "/gprc"); expectEqual(SLASH_GAMEPADRETICLECUSTOMIZER2, "/gamepadreticlecustomizer")
end)

test("its icon in the AddOns list: Code/Media/icon-64.png, shipped", function()
    local function readBytes(path) local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close(); return text end
    local toc = readBytes("GamepadReticleCustomizer.toc"):gsub("\r", "")
    expectEqual(toc:match("## IconTexture: ([^\n]+)"), "Interface\\AddOns\\GamepadReticleCustomizer\\Code\\Media\\icon-64.png")
    expectEqual(readBytes("Code/Media/icon-64.png"):sub(2, 4), "PNG", "a PNG file")
    expectEqual(readBytes(".pkgmeta"):find("- Code/Media/icon-64.png", 1, true), nil, "not left out of the release")
end)

test("debug build: Gamepad Reticle On Target turned off counts as missing, to see its button; the release doesn't", function()
    boot({ reticleOnTargetOff = true })
    expectEqual(control("button", "Reticle on your target").extra.buttonText, "Get the addon",
        "turned off for this character: the button, as players without it see it")
    boot({ reticleOnTargetOff = true, releaseBuild = true })
    expectEqual(control("button", "Reticle on your target"), nil, "the release: installed is installed")
    boot({ reticleOnTargetInstalled = true })
    expectEqual(control("button", "Reticle on your target"), nil, "debug build, turned on: no button")
end)

test("a Get button for each missing sibling, in order, each with its own CurseForge link", function()
    boot()
    expectEqual(control("button", "Camera over shoulder").extra.buttonText, "Get the addon")
    control("button", "Camera over shoulder").extra.onClick()
    expectEqual(popup().editBox:GetText(), "https://www.curseforge.com/projects/1818297")
    control("button", "Reticle on your target").extra.onClick()
    expectEqual(popup().editBox:GetText(), "https://www.curseforge.com/projects/1819101")
    boot({ reticleOnTargetInstalled = true })
    expectEqual(control("button", "Reticle on your target"), nil, "installed: its button gone")
    expectEqual(control("button", "Camera over shoulder") ~= nil, true, "the other one still offered")
end)

-- Each kind of target's own icon.
local function drawnLook() local look = GamepadReticleCustomizer.Reticle.Drawn(); return look.atlas or look.texture end
local function ownIcons() return { friendlyPlayerIcon = "class", otherFactionIcon = "faction", friendlyNpcIcon = "job",
    neutralNpcIcon = "dots", enemyNpcIcon = "swords" } end

test("each kind its own icon: your faction their class, the other faction theirs, enemy NPCs a sword, neutral NPCs gray dots", function()
    boot({ saved = ownIcons() })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5, faction = "Horde" })
    expectEqual(drawnLook(), "classicon-mage", "your faction: the class")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 2, faction = "Alliance" })
    expectEqual(drawnLook(), "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", "the other faction: its badge")
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 4, faction = "Alliance" })
    expectEqual(drawnLook(), "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", "the other faction, unflagged on a PvE realm (neutral): still its badge")
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 1, faction = "Horde" })
    expectEqual(drawnLook(), "classicon-priest", "your own faction, hostile (a duel): its class")
    setTarget({ isPlayer = false, reaction = 2 })
    expectEqual(drawnLook(), "Interface\\Cursor\\Attack", "an enemy NPC: the attack cursor's sword")
    setTarget({ isPlayer = false, reaction = 4 })
    expectEqual(drawnLook(), "SideInProgressquesticon", "a neutral NPC: the game's gray dots")
    boot({ saved = { otherFactionIcon = "class" } })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 2, faction = "Alliance" })
    expectEqual(drawnLook(), "classicon-mage", "the other faction can show their class instead")
    boot({ saved = { friendlyPlayerIcon = "faction" } })
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5, faction = "Horde" })
    expectEqual(drawnLook(), "UI-HUD-UnitFrame-Player-PVP-HordeIcon", "your faction can show its badge too")
    setTarget({ isPlayer = false, reaction = 2 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "enemy NPCs still None: the reticle")
end)

test("friendly NPCs, Their job: the game's own interaction icon for them, else a speech bubble", function()
    boot({ saved = ownIcons() })
    setTarget({ isPlayer = false, reaction = 5, interaction = "buy" }); runUntilNoTimersLeft()
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().cursorUnit, "target", "the game's icon for the target")
    expectEqual(layer().shape.cursorIcon, "buy", "set on our texture by the game")
    setTarget({ isPlayer = false, reaction = 5, interaction = "trainer", inRange = true }); runUntilNoTimersLeft()
    expectEqual(layer().shape.cursorIcon, "trainer", "close enough to interact: still the job, not the controller's button")
    setTarget({ isPlayer = false, reaction = 5 }); runUntilNoTimersLeft()
    expectEqual(drawnLook(), "Crosshair_Speak_128", "no answer from the game: a speech bubble")
    setTarget({ isPlayer = false, reaction = 5, interaction = "Point" }); runUntilNoTimersLeft()
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "nothing to interact with (the plain pointer): the reticle")
    setTarget({ isPlayer = false, reaction = 5, controlled = true }); runUntilNoTimersLeft()
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "another player's pet: the reticle")
end)

test("the sword: gray while none of your spells reach the target, in color once one does", function()
    boot({ saved = { enemyNpcIcon = "swords", neutralNpcIcon = "swords" } })
    game.actions = { [1] = false, [2] = "unknown" }
    setTarget({ isPlayer = false, reaction = 2 })
    expectEqual(layer().shape.desaturated, true, "out of reach: gray")
    local watcher = GamepadReticleCustomizer.Range.watcher
    game.actions[5] = true
    watcher.scripts.OnUpdate(watcher, 1)
    expectEqual(layer().shape.desaturated, false, "a spell reaches it: colored")
    game.actions = { [2] = "unknown" }
    setTarget({ isPlayer = false, reaction = 4 })
    expectEqual(drawnLook(), "Interface\\Cursor\\Attack", "a neutral NPC can have the sword too")
    expectEqual(layer().shape.desaturated, false, "no spell can tell: colored")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 5, faction = "Horde" })
    expectEqual(layer().shape.desaturated, false, "not a sword: never gray")
end)

test("neutral NPCs: a yellow paw or the neutral shield, gray out of reach like the sword", function()
    boot({ saved = { neutralNpcIcon = "paw" } })
    game.actions = { [1] = true }
    setTarget({ isPlayer = false, reaction = 4 })
    expectEqual(drawnLook(), "Interface\\AddOns\\GamepadReticleCustomizer\\Code\\Media\\paw.png")
    expectEqual(colorOf(layer().shape), "1.00 0.82 0.00 1.00", "in reach: yellow")
    game.actions = { [1] = false }
    setTarget({ isPlayer = false, reaction = 4 })
    expectEqual(colorOf(layer().shape), "0.60 0.60 0.60 1.00", "out of reach: gray")
    boot({ saved = { neutralNpcIcon = "shield" } })
    game.actions = { [1] = false }
    setTarget({ isPlayer = false, reaction = 4 })
    expectEqual(layer().shape.desaturated, true, "the shield: gray out of reach")
    for choice, atlas in pairs({ allianceShield = "honorsystem-portrait-alliance", hordeShield = "honorsystem-portrait-horde",
        ffaBadge = "UI-HUD-UnitFrame-Player-PVP-FFAIcon", warMode = "pvptalents-warmode-swords" }) do
        boot({ saved = { neutralNpcIcon = choice } })
        game.actions = { [1] = false }
        setTarget({ isPlayer = false, reaction = 4 })
        expectEqual(drawnLook(), atlas, choice)
        expectEqual(layer().shape.desaturated, true, choice .. ": gray out of reach")
    end
end)

test("on a client without those atlases: the game's icon files instead", function()
    boot({ noKindAtlases = true, saved = ownIcons() })
    setTarget({ isPlayer = false, reaction = 2 })
    expectEqual(drawnLook(), "Interface\\Cursor\\Attack")
    setTarget({ isPlayer = false, reaction = 4 })
    expectEqual(drawnLook(), "Interface\\GossipFrame\\IncompleteQuestIcon")
    setTarget({ isPlayer = false, reaction = 5 }); runUntilNoTimersLeft()
    expectEqual(drawnLook(), "Interface\\GossipFrame\\GossipGossipIcon")
    setTarget({ isPlayer = true, classFile = "MAGE", reaction = 2, faction = "Alliance" })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot", "no faction atlas: the reticle")
end)

test("the player rows are named after the factions, yours first; without a faction, plain words", function()
    boot()
    expectEqual(control("slider", "Horde players") ~= nil, true); expectEqual(control("slider", "Alliance players") ~= nil, true)
    _G.UnitFactionGroup = function(unit) if unit == "player" then return "Alliance" end end
    expectEqual(GamepadReticleCustomizer.KindLabel(GamepadReticleCustomizer.TARGET_KINDS[1]), "Alliance players", "an Alliance character: theirs first")
    expectEqual(GamepadReticleCustomizer.KindLabel(GamepadReticleCustomizer.TARGET_KINDS[2]), "Horde players")
    _G.UnitFactionGroup = function(unit) if unit == "player" then return "Neutral" end end
    expectEqual(GamepadReticleCustomizer.KindLabel(GamepadReticleCustomizer.TARGET_KINDS[1]), "Your faction")
end)

test("each faction its own class icon style, so friend and foe look different; one older style is copied to both", function()
    boot({ jiberish = true, saved = { friendlyPlayerIcon = "class", otherFactionIcon = "class",
        friendlyClassStyle = "game", otherClassStyle = "jiberish:fabled" } })
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 5, faction = "Horde" })
    expectEqual(layer().shape.texture, "classicons-file", "your faction: the game's style (its atlas's file)")
    setTarget({ isPlayer = true, classFile = "PRIEST", reaction = 2, faction = "Alliance" })
    expectEqual(layer().shape.texture, "Interface\\AddOns\\JiberishIcons\\Media\\Class\\fabled", "the other faction: its own style")
    boot({ saved = { classStyle = "jiberish:fabledpixels" } })
    expectEqual(GamepadReticleCustomizerDB.friendlyClassStyle, "jiberish:fabledpixels"); expectEqual(GamepadReticleCustomizerDB.otherClassStyle, "jiberish:fabledpixels")
    expectEqual(GamepadReticleCustomizerDB.classStyle, nil)
end)

test("Their job: drawn once, a short beat after selecting, and again when what you can interact with changes", function()
    boot({ saved = ownIcons() })
    setTarget({ isPlayer = false, reaction = 5, interaction = "buy" })
    expectEqual(#game.timers, 1, "one draw, a beat later: no wrong icon first")
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().cursorUnit, nil, "the reticle moving onto the nameplate meanwhile draws nothing")
    runUntilNoTimersLeft()
    expectEqual(layer().shape.cursorIcon, "buy")
    game.target.interaction = "repair"
    game.fire("PLAYER_SOFT_INTERACT_CHANGED")
    expectEqual(layer().shape.cursorIcon, "repair", "drawn again when the interaction changes")
    setTarget({ isPlayer = false, reaction = 2 })
    expectEqual(drawnLook(), "Interface\\Cursor\\Attack", "another kind: drawn at once")
end)

test("our icon on the target hides the game's interaction icon on its nameplate; the reticle's shape doesn't", function()
    boot({ saved = { enemyNpcIcon = "swords" } })
    local iconSpot = { alpha = 0.9 }
    function iconSpot:SetAlpha(alpha) self.alpha = alpha end
    function iconSpot:GetAlpha() return self.alpha end
    local plate = { UnitFrame = { SoftTargetFrame = iconSpot } }
    C_NamePlate.GetNamePlateForUnit = function(unit) if unit == "target" and game.target then return plate end end
    setTarget({ isPlayer = false, reaction = 2 })
    expectEqual(iconSpot.alpha, 0, "only our icon shows")
    setTarget({ isPlayer = false, reaction = 5 })
    expectEqual(GamepadReticleCustomizer.Reticle.Drawn().icon, "dot")
    expectEqual(iconSpot.alpha, 0.9, "our reticle's shape: the game's icon back, at its own alpha")
end)

test("the screenshot tour stays out of the release: ignored by .pkgmeta, in the .toc's development block", function()
    assert(readFile(".pkgmeta"):find("\n  %- Code/Showcase%.lua\n"), ".pkgmeta ignores Showcase.lua, alone on its line")
    expectEqual(table.concat(tocFiles(true), ","):find("Code/Showcase.lua", 1, true), nil, "not in the release .toc")
    expectEqual(table.concat(tocFiles(false), ","):find("Code/Showcase.lua", 1, true) ~= nil, true, "in the development one")
end)

test("in a dungeon (the target's GUID and name secret), Debug records each new target once, with no error", function()
    boot({ saved = ownIcons() })
    _G.UnitGUID = function(unit) if unit == "target" then return secretValue() end return "Player-93-0A1B2C3D" end
    _G.UnitName = function(unit) if unit == "target" then return secretValue() end return "Artio" end
    setTarget({ isPlayer = false, reaction = 2, interaction = "attack", plateUnit = "nameplate4" })
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")   -- drawn again, the same target
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
    local records = GamepadReticleCustomizerDebugDB.interactionIcons
    expectEqual(#records, 1, "one record for one target")
    expectEqual(records[1].name, "nil", "a hidden name is saved as unknown")
    setTarget({ isPlayer = false, reaction = 5, interaction = "buy", plateUnit = "nameplate5" })
    expectEqual(#records, 1, "a job icon's target: not before the job icon's wait")
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
    expectEqual(#records, 1, "still waiting: a redraw meanwhile records nothing")
    runUntilNoTimersLeft()
    expectEqual(#records, 2, "after the wait: one more record")
    expectEqual(records[2].texture, "Cursor Crosshair_buy_64", "the new target's icon")
end)

test("in a dungeon, a reticle anchor the game hides (a secret value) counts as on the nameplate, with no error", function()
    boot()
    setTarget({ isPlayer = false, reaction = 2, plateUnit = "nameplate4" })
    function GamepadReticle:GetPoint() return "CENTER", secretValue(), "BOTTOM", 0, 0 end
    expectEqual(GamepadReticleCustomizer.ReticleOnNameplate(), true)
end)

-- Nearby: object icons (the game's CVars) and quest icons on nameplates

local function cvarsText()
    local names = { "SoftTargetInteract", "SoftTargetInteractArc", "SoftTargetIconGameObject", "nameplateGameObjectMaxDistance" }
    local values = {}
    for _, name in ipairs(names) do values[#values + 1] = C_CVar.GetCVar(name) end   -- what the game uses
    return table.concat(values, " ")
end
local OUR_CVARS = "3 2 1 60"

-- The controller UI's own temporary values (Blizzard_Gamepad/Core.lua).
local CONTROLLER_TEMP_CVARS = { SoftTargetInteract = "1", SoftTargetInteractArc = "1", SoftTargetIconGameObject = "1" }
local function copyOf(values) local copy = {}; for name, value in pairs(values) do copy[name] = value end; return copy end

test("object icons: off at first, nothing changed; on, ours as temporary values, never saved; off, as before", function()
    boot()
    expectEqual(GamepadReticleCustomizerDB.objectIcons, false)
    setting("objectIcons"):SetValue(true)
    expectEqual(cvarsText(), OUR_CVARS)
    expectEqual(#game.cvarsSet, 0, "your saved settings untouched")
    setting("objectIcons"):SetValue(false)
    expectEqual(cvarsText(), "1 0 0 30", "yours back")
    expectEqual(next(game.tempCVars), nil, "no temporary value left")
end)

test("object icons: over the controller UI's temporary values, and those back when off", function()
    boot({ tempCVars = copyOf(CONTROLLER_TEMP_CVARS) })
    setting("objectIcons"):SetValue(true)
    expectEqual(cvarsText(), OUR_CVARS)
    setting("objectIcons"):SetValue(false)
    expectEqual(cvarsText(), "1 1 1 30", "the controller UI's back")
    expectEqual(game.tempCVars.SoftTargetIconGameObject, "1", "the one already at ours never touched")
    expectEqual(#game.cvarsSet, 0)
end)

test("object icons: each loading screen sets ours again; a reload starts over; one changed meanwhile isn't put back", function()
    boot()
    setting("objectIcons"):SetValue(true)
    game.fire("PLAYER_ENTERING_WORLD")
    expectEqual(cvarsText(), OUR_CVARS)
    local saved = GamepadReticleCustomizerDB
    boot({ saved = saved, tempCVars = copyOf(CONTROLLER_TEMP_CVARS) })   -- the game set its own again
    expectEqual(cvarsText(), OUR_CVARS, "ours at login")
    game.tempCVars.SoftTargetInteractArc = "0"   -- something else changed it
    setting("objectIcons"):SetValue(false)
    expectEqual(cvarsText(), "1 0 1 30", "the controller UI's back, the changed one left as it is")
end)

test("object icons: in a fight the change waits for its end (the game refuses secure CVars then)", function()
    boot()
    game.combat = true
    setting("objectIcons"):SetValue(true)
    expectEqual(cvarsText(), "1 0 0 30", "nothing in the fight, no error")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    expectEqual(cvarsText(), OUR_CVARS)
end)

-- A nameplate for a unit, with its tooltip lines, shown as the game does.
local function showPlate(unit, tooltipLines)
    game.plates[unit] = newRegion(UIParent)
    game.tooltips[unit] = tooltipLines
    game.fire("NAME_PLATE_UNIT_ADDED", unit)
    return game.plates[unit]
end
local function objectiveLine(text) return { type = Enum.TooltipDataLineType.QuestObjective, leftText = text } end
local function questIconsOf(plate)
    for _, frame in ipairs(game.frames) do
        if frame.parent == plate and frame.kill then return frame end
    end
end
-- "kill loot" as shown: "sword", "bag", "sword bag" (the sword nearest), or "none".
local function shownIcons(plate)
    local icons = questIconsOf(plate)
    if not icons then return "none" end
    local shown = {}
    for _, icon in ipairs({ { texture = icons.kill, name = "sword" }, { texture = icons.loot, name = "bag" } }) do
        if icon.texture:IsShown() then shown[#shown + 1] = { name = icon.name, offset = icon.texture.offset[1] } end
    end
    table.sort(shown, function(first, second) return first.offset > second.offset end)
    local names = {}
    for _, icon in ipairs(shown) do names[#names + 1] = icon.name end
    return #names > 0 and table.concat(names, " ") or "none"
end
local function questLog()
    game.quests = { { questID = 1221, objectives = {
        { text = "0/6 Blueleaf Tuber", type = "item", finished = false },
        { text = "3/8 Boar slain", type = "monster", finished = false },
        { text = "8/8 Kobold slain", type = "monster", finished = true },
        { text = "Speak to Mankrik", type = "event", finished = false },
    } } }
end

test("quest icons: off at first; on, a sword to kill, a bag for an item it drops, both side by side", function()
    boot()
    questLog()
    expectEqual(GamepadReticleCustomizerDB.questIcons, false)
    local boar = showPlate("nameplate1", { { type = 2, leftText = "Boar" }, objectiveLine("3/8 Boar slain") })
    expectEqual(shownIcons(boar), "none", "off: no icons, no frame made")
    setting("questIcons"):SetValue(true)
    expectEqual(shownIcons(boar), "sword")
    near(questIconsOf(boar).kill.offset[1], -6, "6 left of the nameplate")
    local tuber = showPlate("nameplate2", { objectiveLine("0/6 Blueleaf Tuber") })
    expectEqual(shownIcons(tuber), "bag")
    near(questIconsOf(tuber).loot.offset[1], -6, "alone: in the sword's place")
    local both = showPlate("nameplate3", { objectiveLine("0/6 Blueleaf Tuber"), objectiveLine("3/8 Boar slain") })
    expectEqual(shownIcons(both), "sword bag")
    near(questIconsOf(both).loot.offset[1], -29, "beside the sword: 6 + 20 + 3")
    expectEqual(shownIcons(showPlate("nameplate4", { objectiveLine("8/8 Kobold slain") })), "none", "a finished objective")
    expectEqual(shownIcons(showPlate("nameplate5", { objectiveLine("Speak to Mankrik") })), "none", "not a kill or an item")
    expectEqual(shownIcons(showPlate("nameplate6", { objectiveLine("2/8 Wolf slain") })), "none", "not in your quest log")
    expectEqual(questIconsOf(boar).kill.atlas, "Crosshair_Attack_32"); expectEqual(questIconsOf(boar).loot.atlas, "Crosshair_pickup_32")
    setting("questIcons"):SetValue(false)
    expectEqual(shownIcons(boar) .. "," .. shownIcons(both), "none,none", "off: gone")
end)

test("quest icons: the quest log changing redraws them (an objective done: its icon gone), once per burst", function()
    boot()
    questLog()
    setting("questIcons"):SetValue(true)
    local boar = showPlate("nameplate1", { objectiveLine("3/8 Boar slain") })
    game.quests[1].objectives[2].finished = true
    game.fire("QUEST_LOG_UPDATE"); game.fire("QUEST_LOG_UPDATE")
    expectEqual(#game.timers, 1, "one redraw for the burst")
    runNextFrame()
    expectEqual(shownIcons(boar), "none")
end)

test("quest icons: tooltip text the game hides (a secret value) is never compared: kept, then read after the fight", function()
    boot()
    questLog()
    setting("questIcons"):SetValue(true)
    local boar = showPlate("nameplate1", { objectiveLine("3/8 Boar slain") })
    game.tooltips.nameplate1 = { objectiveLine(secretValue()) }   -- the fight starts
    game.fire("QUEST_LOG_UPDATE"); runNextFrame()
    expectEqual(shownIcons(boar), "sword", "a nameplate already shown keeps its icons, no error")
    local wolf = showPlate("nameplate2", { { type = secretValue() } })
    expectEqual(shownIcons(wolf), "none", "a nameplate new in the fight: none, no error")
    local secretTooltip = showPlate("nameplate3", secretValue())
    expectEqual(shownIcons(secretTooltip), "none", "a whole tooltip hidden")
    expectEqual(shownIcons(showPlate("nameplate4", { forbidden = true })), "none", "lines the game forbids")
    game.tooltips.nameplate1 = { objectiveLine("3/8 Boar slain") }   -- the fight ends
    game.tooltips.nameplate2 = { objectiveLine("3/8 Boar slain") }
    game.fire("PLAYER_REGEN_ENABLED")
    expectEqual(shownIcons(boar) .. "," .. shownIcons(wolf), "sword,sword", "read again")
end)

test("quest icons: a nameplate reused for another unit loses the first one's icons; forbidden ones left alone", function()
    boot()
    questLog()
    setting("questIcons"):SetValue(true)
    local plate = showPlate("nameplate1", { objectiveLine("3/8 Boar slain") })
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    game.plates.nameplate1 = nil
    game.plates.nameplate7 = plate   -- the game's same frame, for another unit
    game.tooltips.nameplate7 = { objectiveLine(secretValue()) }
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
    expectEqual(shownIcons(plate), "none", "unreadable for the new unit: none, not the boar's")
    local forbiddenPlate = newRegion(UIParent)
    forbiddenPlate.forbidden = true
    game.plates.nameplate8, game.tooltips.nameplate8 = forbiddenPlate, { objectiveLine("3/8 Boar slain") }
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
    expectEqual(questIconsOf(forbiddenPlate), nil, "nothing made on a forbidden nameplate")
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
