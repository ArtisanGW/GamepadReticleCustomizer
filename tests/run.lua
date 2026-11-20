-- GamepadCrosshairCustomizer against a fake game: the controller's crosshair, frames
-- and textures, the Settings API, the color picker, a controller, addons installed
-- or not. From GamepadCrosshairCustomizer:  luajit tests/run.lua
local reportLine = print   -- the tests replace print to read what the addon says
local failed, passed = 0, 0
local only = os.getenv("GCC_TEST")   -- run only the tests whose name holds this
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
    local toc = readFile("GamepadCrosshairCustomizer.toc"):gsub("\r", "")
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
    function region:SetAllPoints() end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:GetWidth() return self.width end
    function region:GetHeight() return self.height end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetShown(shown) self.shown = shown and true or false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:GetAlpha() return self.alpha end
    function region:SetTexture(path) self.texture = path; return true end
    function region:GetTexture() return self.texture end
    function region:SetColorTexture(red, green, blue, alpha) self.color = { red, green, blue, alpha } end
    function region:SetVertexColor(red, green, blue, alpha) self.color = { red, green, blue, alpha or 1 } end
    function region:GetVertexColor() return unpack(self.color) end
    function region:GetEffectiveScale() return 1 end
    function region:GetCenter() return 640, 400 end
    function region:SetFrameStrata() end
    function region:EnableMouse() end
    function region:SetText(text) self.text = text end
    function region:GetText() return self.text end
    function region:SetWidth(width) self.width = width end
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
    local function fire(event, ...)
        for _, frame in ipairs(game.frames) do if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end end
    end
    game.fire = fire
    _G.InputUtil = { IsGamepadUIEnabled = function() return options.keyboard ~= true end }
    _G.GetTime = function() return game.time end
    _G.C_Timer = { After = function(_, fn) game.timers[#game.timers + 1] = fn end }
    _G.InCombatLockdown = function() return game.combat == true end
    _G.UIParent = newRegion(nil)
    function UIParent:GetHeight() return 768 end
    _G.GetPhysicalScreenSize = function() return 2560, 1440 end
    _G.GetBuildInfo = function() return "1.60.1", "70959", "", 16001 end
    _G.UnitExists = function() return false end
    _G.date = os.date
    _G.CreateFrame = function(_, name, parent)
        local frame = newRegion(parent)
        frame.events, frame.scripts = {}, {}
        if name then _G[name] = frame end
        function frame:RegisterEvent(eventName) self.events[eventName] = true end
        function frame:UnregisterEvent(eventName) self.events[eventName] = nil end
        function frame:SetScript(scriptType, handler) self.scripts[scriptType] = handler end
        game.frames[#game.frames + 1] = frame
        return frame
    end
    _G.C_AddOns = { DoesAddOnExist = function(name) return name == "JiberishIcons" and options.jiberish == true end }
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
        CreateCheckbox = function(_, setting) addControl("checkbox", setting) end,
        CreateSlider = function(_, setting, sliderOptions) addControl("slider", setting, sliderOptions) end,
        CreateSliderOptions = function(minimum, maximum, step)
            return { minimum = minimum, maximum = maximum, step = step, SetLabelFormatter = function(self, _, fn) self.format = fn end }
        end,
        CreateDropdown = function(_, setting, getOptions, tooltip) addControl("dropdown", setting, { getOptions = getOptions, tooltip = tooltip }) end,
        CreateControlTextContainer = function()
            local container = { data = {} }
            function container:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
            function container:GetData() return self.data end
            return container
        end,
        CreateColorSwatch = function(_, setting) addControl("swatch", setting) end,
        RegisterAddOnCategory = function(category) game.category = category end,
        OpenToCategory = function(id) game.opened = id end,
    }
    _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip, addSearchTags)
        assert(addSearchTags ~= nil, "the game asserts addSearchTags isn't nil")
        return { name = name, buttonText = buttonText, onClick = onClick, tooltip = tooltip }
    end
    _G.SlashCmdList = {}
    game.bindings = {}
    _G.SetOverrideBindingClick = function(_, _, key, buttonName) game.bindings[key] = buttonName end
    -- The controller UI's crosshair: Blizzard's dot, white, never tinted by the game.
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
    _G.GamepadCrosshairCustomizerDB = options.saved
    _G.GamepadCrosshairCustomizerDebugDB = options.debugSaved
    _G.GamepadCrosshairCustomizerDebugBox = nil
    _G.print = function(t) game.printed[#game.printed + 1] = t end
    local namespace = {}
    for _, fileName in ipairs(tocFiles(options.releaseBuild)) do assert(loadfile(fileName))("GamepadCrosshairCustomizer", namespace) end
    fire("ADDON_LOADED", "GamepadCrosshairCustomizer")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD")
end
local function frame() local timers = game.timers; game.timers = {}; for _, fn in ipairs(timers) do fn() end end
local function runUntilNoTimersLeft()
    for _ = 1, 200 do if #game.timers == 0 then return end; frame() end
    error("the timers never ended")
end

local function layer() return GamepadCrosshairCustomizer.Crosshair.Layer() end
local function colorOf(region)
    return string.format("%.2f %.2f %.2f %.2f", region.color[1], region.color[2], region.color[3], region.color[4])
end
local function setting(key) return game.settings["GamepadCrosshairCustomizer_" .. key] end
local function control(kind, labelOrName)
    for _, entry in ipairs(game.controls) do
        local label = entry.setting and entry.setting.label or (entry.extra and entry.extra.name)
        if entry.kind == kind and label == labelOrName then return entry end
    end
end
local function controlList()
    local labels = {}
    for _, entry in ipairs(game.controls) do
        labels[#labels + 1] = entry.kind .. ":" .. (entry.setting and entry.setting.label or entry.extra.name)
    end
    return table.concat(labels, ", ")
end
local function dropdownIds()
    local ids = {}
    for _, option in ipairs(control("dropdown", "Shape").extra.getOptions()) do ids[#ids + 1] = option.value end
    return ids
end

-- The settings page

test("its page under Options > AddOns, in order, with the defaults; /gcc opens it", function()
    boot()
    eq(game.category.name, "Gamepad Crosshair Customizer")
    eq(controlList(), "checkbox:Enable, dropdown:Shape, slider:Size, swatch:Color, slider:Border, swatch:Border color, "
        .. "button:Custom texture, button:More shapes")
    local saved = GamepadCrosshairCustomizerDB
    eq(saved.enabled, true); eq(saved.color, "FFFFFFFF"); eq(saved.size, 4); eq(saved.borderSize, 0)
    eq(saved.borderColor, "000000FF"); eq(saved.icon, "dot"); eq(saved.customTexture, "")
    eq(control("slider", "Size").extra.format(4), "4 (the game's)"); eq(control("slider", "Size").extra.format(24), "24")
    eq(control("slider", "Border").extra.format(0), "Off"); eq(control("slider", "Border").extra.format(3), "3")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("")
    eq(game.opened, 42)
end)

-- Drawing

test("at login: our crosshair drawn on the game's, the game's dot see-through, your settings on it", function()
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

test("the color: 32 bits RRGGBBAA from /gcc, six digits opaque, a wrong one changes nothing", function()
    boot()
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("FF3030CC")
    eq(GamepadCrosshairCustomizerDB.color, "FF3030CC")
    eq(colorOf(layer().shape), "1.00 0.19 0.19 0.80", "drawn at once")
    eq(game.printed[#game.printed]:find("FF3030CC", 1, true) ~= nil, true, "and says so")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("nonsense")
    eq(GamepadCrosshairCustomizerDB.color, "FF3030CC", "a wrong color changes nothing")
    eq(game.printed[#game.printed]:find("usage", 1, true) ~= nil, true, "and says how")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("#00ff00")
    eq(GamepadCrosshairCustomizerDB.color, "00FF00FF", "six digits: opaque")
end)

test("the two swatches speak AARRGGBB, each for its own color; the opacity is kept", function()
    boot({ saved = { color = "00FF0066", borderSize = 2 } })
    local colorSwatch, borderSwatch = control("swatch", "Color").setting, control("swatch", "Border color").setting
    eq(colorSwatch.getValue(), "FF00FF00", "alpha FF, the color")
    colorSwatch.setValue("ff0000ff")
    eq(GamepadCrosshairCustomizerDB.color, "0000FF66", "the picked color, the opacity kept")
    colorSwatch.setValue("nonsense")
    eq(GamepadCrosshairCustomizerDB.color, "0000FF66", "a wrong value changes nothing")
    borderSwatch.setValue("ffffffff")
    eq(GamepadCrosshairCustomizerDB.borderColor, "FFFFFFFF", "the border's own color")
    eq(GamepadCrosshairCustomizerDB.color, "0000FF66", "the crosshair's untouched")
    eq(colorOf(layer().border), "1.00 1.00 1.00 1.00", "drawn at once")
end)

test("the picker's opacity bar is for the color whose swatch opened it", function()
    boot({ saved = { color = "FFFFFF80", borderColor = "00000040", borderSize = 1 } })
    control("swatch", "Border color").setting.getValue()
    ColorPickerFrame:Show()
    near(game.picker.alpha, 0x40 / 255, "the border's opacity on the bar")
    ColorPickerFrame.Content.ColorPicker:SetColorAlpha(1); ColorPickerFrame.opacityFunc()
    eq(GamepadCrosshairCustomizerDB.borderColor, "000000FF", "the bar sets the border's")
    eq(GamepadCrosshairCustomizerDB.color, "FFFFFF80", "not the crosshair's")
    ColorPickerFrame:Hide()
    game.time = game.time + 5
    control("swatch", "Color").setting.getValue()
    ColorPickerFrame:Show()
    near(game.picker.alpha, 0x80 / 255, "then the crosshair's own")
end)

test("controller: while the picker is open for our color, the sticks and D-pad drive it", function()
    boot()
    local driver = GamepadCrosshairCustomizer.PickerSticks.driver
    local function step(seconds) driver.scripts.OnUpdate(driver, seconds) end
    ColorPickerFrame:Show()
    eq(driver.shown, false, "a picker opened by something else (the chat settings): left to the game")
    eq(ColorPickerFrame.hasOpacity, nil, "and no opacity bar put on it")
    ColorPickerFrame:Hide()
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("FFFFFF80")
    control("swatch", "Color").setting.getValue()   -- the swatch reads the color as it opens the picker
    game.time = game.time + 0.1
    ColorPickerFrame:Show()
    eq(driver.shown, true, "opened for the crosshair color")
    eq(ColorPickerFrame.hasOpacity, true, "the opacity bar put on the picker")
    near(game.picker.alpha, 128 / 255, "at the crosshair's opacity")
    game.padUp = true; step(0.5)
    near(game.picker.alpha, 128 / 255 + 0.25, "D-pad up: more solid (0.5 a second)")
    eq(GamepadCrosshairCustomizerDB.color:sub(7, 8), string.format("%02X", math.floor((128 / 255 + 0.25) * 255 + 0.5)),
        "and the crosshair with it")
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
    eq(GamepadCrosshairCustomizer.PickerSticks.driver.shown, false)
end)

-- Shapes

test("shapes: the game's dot, its 8 raid markers and a custom texture; no Jiberish ones without it", function()
    boot()
    local ids = dropdownIds()
    eq(table.concat(ids, ","), "dot,marker1,marker2,marker3,marker4,marker5,marker6,marker7,marker8,custom")
    setting("icon"):SetValue("marker8")
    eq(layer().shape.texture, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", "the skull")
    eq(GamepadCrosshairCustomizer.Crosshair.Drawn().icon, "marker8")
    setting("icon"):SetValue("jiberish:x-bold")
    eq(GamepadCrosshairCustomizer.Crosshair.Drawn().icon, "dot", "a Jiberish shape without the addon: the game's dot shape")
    setting("icon"):SetValue("custom")
    eq(GamepadCrosshairCustomizer.Crosshair.Drawn().icon, "dot", "custom with no path yet: the dot")
end)

test("with JiberishUI Fabled Icons installed: its 16 shapes listed and drawn from its folder, credited, no install button", function()
    boot({ jiberish = true })
    local ids = dropdownIds()
    eq(#ids, 26, "the dot, 8 markers, 16 Jiberish shapes, custom")
    eq(ids[10], "jiberish:circle-bold"); eq(ids[25], "jiberish:x-thin")
    setting("icon"):SetValue("jiberish:splitplus-thin")
    eq(layer().shape.texture, "Interface\\AddOns\\JiberishIcons\\Media\\Crosshair\\splitplus-thin-128")
    eq(control("button", "More shapes"), nil, "no install button when it's there")
    eq(control("dropdown", "Shape").extra.tooltip:find("Shapes from JiberishUI Fabled Icons", 1, true) ~= nil, true,
        "credited, as its license asks")
end)

test("without it: the install button shows the link to copy", function()
    boot()
    control("button", "More shapes").extra.onClick()
    local box = GamepadCrosshairCustomizer.TextBox.box
    eq(box:IsShown(), true)
    eq(box.editBox:GetText(), "https://www.curseforge.com/wow/addons/jiberish-fabled-icons")
    eq(box.editBox.highlighted, true, "selected, ready for Ctrl+C")
    eq(box.okButton:IsShown(), false, "nothing to confirm: only Close")
    box.closeButton:Click()
    eq(box:IsShown(), false)
end)

test("a custom texture: typed in the box or with /gcc texture, and the Shape picks it", function()
    boot()
    control("button", "Custom texture").extra.onClick()
    local box = GamepadCrosshairCustomizer.TextBox.box
    eq(box.okButton:IsShown(), true)
    box.editBox:SetText("  Interface\\Icons\\INV_Misc_QuestionMark  ")
    box.okButton:Click()
    eq(GamepadCrosshairCustomizerDB.customTexture, "Interface\\Icons\\INV_Misc_QuestionMark", "trimmed")
    eq(GamepadCrosshairCustomizerDB.icon, "custom", "the Shape set to it")
    eq(layer().shape.texture, "Interface\\Icons\\INV_Misc_QuestionMark")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("texture Interface\\Icons\\Spell_Nature_Starfall")
    eq(layer().shape.texture, "Interface\\Icons\\Spell_Nature_Starfall")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("texture")
    eq(game.printed[#game.printed]:find("usage", 1, true) ~= nil, true, "no path: says how")
end)

-- /gcc debug, run here against the fake game

local function failedChecks(run)
    local lines = {}
    for _, check in ipairs(run.checks) do
        if check.result == "fail" then
            lines[#lines + 1] = check.name .. ": expected " .. tostring(check.expected) .. ", got " .. tostring(check.actual)
        end
    end
    return table.concat(lines, "\n")
end

test("/gcc debug: every look checked, each step marked in the corner, your settings back, the reload box", function()
    for _, jiberish in ipairs({ false, true }) do
        boot({ jiberish = jiberish, saved = { color = "3961CDFF", size = 7, icon = "marker2" } })
        SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("debug")
        local debugSuite = GamepadCrosshairCustomizer.Debug
        eq(debugSuite.marker:IsShown(), true, "the corner square")
        eq(math.floor(debugSuite.marker.texture.color[3] * 255 + 0.5), 8, "blue: step 1 x 8")
        runUntilNoTimersLeft()
        local run = GamepadCrosshairCustomizerDebugDB.runs[1]
        eq(failedChecks(run), "", "no failed check (Jiberish " .. tostring(jiberish) .. ")")
        eq(run.failed, 0); eq(run.skipped, 0)
        eq(run.passed > 100, true, "passed " .. run.passed)
        eq(#run.steps, #debugSuite.STEPS, "one entry per step")
        -- The fake's center (640, 400) on a 1440 px tall screen (768 units): 1.875 px a unit, y from the top.
        eq(run.steps[2].onScreen.x, 1200, "where the crosshair is, in screen pixels")
        eq(run.steps[2].onScreen.y, 1440 - 750, "from the top")
        eq(run.environment.jiberishInstalled, jiberish)
        eq(debugSuite.marker:IsShown(), false, "the square gone: done")
        eq(GamepadCrosshairCustomizerDB.color, "3961CDFF", "your settings back")
        eq(GamepadCrosshairCustomizerDB.size, 7); eq(GamepadCrosshairCustomizerDB.icon, "marker2")
        eq(layer().shape.texture, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", "and drawn")
        eq(GamepadCrosshairCustomizerDebugDB.settingsToRestore, nil)
        local reloadBox = GamepadCrosshairCustomizerDebugBox
        eq(reloadBox:IsShown(), true, "the reload box")
        eq(reloadBox.reloadButton.attributes.macrotext, "/reload")
    end
end)

test("/gcc debug: waits for the crosshair on screen before its first step (the cursor hides it)", function()
    boot()
    GamepadReticle.Icons:Hide()   -- the cursor shows, as just after a reload
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("debug")
    local debugSuite = GamepadCrosshairCustomizer.Debug
    eq(colorOf(debugSuite.marker.texture), "1.00 1.00 0.00 1.00", "yellow: waiting")
    frame(); frame(); frame()
    eq(colorOf(debugSuite.marker.texture), "1.00 1.00 0.00 1.00", "still waiting, no step yet")
    GamepadReticle.Icons:Show()
    frame()
    eq(math.floor(debugSuite.marker.texture.color[3] * 255 + 0.5), 8, "step 1 once it shows")
    runUntilNoTimersLeft()
    local run = GamepadCrosshairCustomizerDebugDB.runs[1]
    eq(run.environment.crosshairWaitSeconds, 2, "waited 2 s (4 polls)")
    eq(run.environment.crosshairOnScreenAtStart, true)

    boot()
    GamepadCrosshairCustomizer.Debug.CROSSHAIR_WAIT_SECONDS = 1
    GamepadReticle.Icons:Hide()
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("debug")
    runUntilNoTimersLeft()
    eq(GamepadCrosshairCustomizerDebugDB.runs[1].environment.crosshairOnScreenAtStart, false, "never showed: runs anyway, says so")
end)

test("/gcc debug: Alt+Ctrl+Shift+C starts it too (for the screenshot script)", function()
    boot()
    eq(game.bindings["ALT-CTRL-SHIFT-C"], "GamepadCrosshairCustomizerDebugStart")
    _G[game.bindings["ALT-CTRL-SHIFT-C"]]:Click()
    eq(GamepadCrosshairCustomizer.Debug.marker:IsShown(), true, "running")
    runUntilNoTimersLeft()
    eq(GamepadCrosshairCustomizerDebugDB.runs[1].failed, 0)
end)

test("/gcc debug: a fight stops it, your settings back, the square red", function()
    boot({ saved = { color = "3961CDFF" } })
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("debug")
    frame(); frame()
    game.combat = true
    game.fire("PLAYER_REGEN_DISABLED")
    eq(GamepadCrosshairCustomizerDebugDB.runs[1].stopped, "combat")
    eq(GamepadCrosshairCustomizerDB.color, "3961CDFF")
    eq(GamepadCrosshairCustomizer.Debug.marker.texture.color[1], 1, "red")
    runUntilNoTimersLeft()
    eq(#GamepadCrosshairCustomizerDebugDB.runs, 1, "nothing ran after the stop")
end)

test("/gcc debug: a reload in the middle of a run puts your settings back at the next login", function()
    boot({ saved = { color = "FF0000FF", size = 48 },
        debugSaved = { runs = {}, settingsToRestore = { color = "3961CDFF", size = 7, enabled = true } } })
    eq(GamepadCrosshairCustomizerDB.color, "3961CDFF"); eq(GamepadCrosshairCustomizerDB.size, 7)
    eq(GamepadCrosshairCustomizerDebugDB.settingsToRestore, nil)
    eq(layer().shape:GetWidth(), 7, "and drawn")
end)

-- The addon and its release

test("an addon of its own: needs no other addon; listed under Gamepad", function()
    local toc = readFile("GamepadCrosshairCustomizer.toc")
    eq(toc:find("Dependencies", 1, true), nil); eq(toc:find("OptionalDeps", 1, true), nil)
    eq(toc:match("## Category: ([^\r\n]+)"), "Gamepad", "under Gamepad in the AddOns list, the game's own word")
end)

test("the release leaves Debug.lua out: ignored by .pkgmeta, and gone from the release .toc", function()
    assert(readFile(".pkgmeta"):find("\n  %- Debug%.lua\n"), ".pkgmeta ignores Debug.lua, alone on its line")
    eq(table.concat(tocFiles(true), ","),
        "SavedSettings.lua,Color.lua,Icons.lua,Crosshair.lua,PickerSticks.lua,TextBox.lua,GamepadCrosshairCustomizer.lua")
    eq(tocFiles()[#tocFiles()], "Debug.lua", "the repo's .toc loads it last")
end)

test("without Debug.lua (the release), the addon works and /gcc debug opens the settings", function()
    boot({ releaseBuild = true })
    eq(GamepadCrosshairCustomizer.Debug, nil)
    eq(layer():IsShown(), true)
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("debug")
    eq(game.opened, 42)
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
