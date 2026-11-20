-- GamepadCrosshairCustomizer against a fake game: the controller's crosshair, the
-- Settings API, the color picker and a controller. From GamepadCrosshairCustomizer:
--   luajit tests/run.lua
local reportLine = print   -- the tests replace print to read what the addon says
local failed, passed = 0, 0
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; reportLine("FAIL " .. name .. "\n" .. err) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function near(a, b, msg) if math.abs(a - b) > 0.01 then error((msg or "") .. ": expected " .. b .. ", got " .. a, 2) end end
local function readFile(path) local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text end

-- The files the .toc loads, in its order.
local function tocFiles()
    local files = {}
    for line in readFile("GamepadCrosshairCustomizer.toc"):gsub("\r", ""):gmatch("[^\n]+") do
        if not line:find("^#") then files[#files + 1] = line end
    end
    return files
end

local game
local function boot(gamepad, saved)
    game = { frames = {}, settings = {}, callbacks = {}, time = 100, printed = {} }
    local function fire(event, ...)
        for _, f in ipairs(game.frames) do if f.ev[event] and f.script then f.script(f, event, ...) end end
    end
    game.fire = fire
    _G.InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
    _G.GetTime = function() return game.time end
    _G.CreateFrame = function()
        local fakeFrame = { ev = {} }
        function fakeFrame:RegisterEvent(eventName) self.ev[eventName] = true end
        function fakeFrame:UnregisterEvent(eventName) self.ev[eventName] = nil end
        function fakeFrame:SetScript(scriptType, handler)
            if scriptType == "OnUpdate" then self.update = handler else self.script = handler end
        end
        function fakeFrame:Show() self.shown = true end
        function fakeFrame:Hide() self.shown = false end
        game.frames[#game.frames + 1] = fakeFrame
        return fakeFrame
    end
    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },
        RegisterVerticalLayoutCategory = function(name) return { name = name, GetID = function() return 42 end } end,
        RegisterAddOnSetting = function(_, variable, key, tbl, _, label, def)
            if tbl[key] == nil then tbl[key] = def end
            local s = { variable = variable, key = key, tbl = tbl, label = label }
            game.settings[variable] = s
            return s
        end,
        SetOnValueChangedCallback = function(variable, fn) game.callbacks[variable] = fn end,
        RegisterProxySetting = function(_, variable, _, label, _, getValue, setValue)
            local s = { variable = variable, label = label, getValue = getValue, setValue = setValue }
            game.settings[variable] = s
            return s
        end,
        CreateCheckbox = function() end,
        CreateColorSwatch = function(_, setting) game.swatch = setting end,
        RegisterAddOnCategory = function(cat) game.category = cat end,
        OpenToCategory = function(id) game.opened = id end,
    }
    _G.SlashCmdList = {}
    -- The controller UI's crosshair: Blizzard's dot, white, never tinted by the game.
    _G.GamepadReticle = { Icons = { StandardIcon = {
        color = { 1, 1, 1, 1 },
        GetVertexColor = function(self) return unpack(self.color) end,
        SetVertexColor = function(self, r, g, b, a) self.color = { r, g, b, a } end,
    } } }
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
    _G.GamepadCrosshairCustomizerDB = saved
    _G.print = function(t) game.printed[#game.printed + 1] = t end
    local namespace = {}
    for _, fileName in ipairs(tocFiles()) do assert(loadfile(fileName))("GamepadCrosshairCustomizer", namespace) end
    fire("ADDON_LOADED", "GamepadCrosshairCustomizer")
    fire("PLAYER_ENTERING_WORLD")
end

local function dotColor()
    local color = GamepadReticle.Icons.StandardIcon.color
    return string.format("%.2f %.2f %.2f %.2f", color[1], color[2], color[3], color[4])
end
local function setEnabled(value)
    local setting = game.settings.GamepadCrosshairCustomizer_enabled
    setting.tbl[setting.key] = value
    game.callbacks[setting.variable](nil, setting, value)
end

test("registers its page under Options > AddOns, with the defaults; /gcc opens it", function()
    boot(true, nil)
    eq(game.category.name, "Gamepad Crosshair Customizer")
    eq(GamepadCrosshairCustomizerDB.enabled, true); eq(GamepadCrosshairCustomizerDB.color, "FFFFFFFF", "white by default")
    eq(game.settings.GamepadCrosshairCustomizer_enabled.label, "Enable")
    eq(game.swatch.label, "Crosshair color", "the settings page's own swatch, which opens the picker itself")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("")
    eq(game.opened, 42)
end)

test("your saved color is on the dot from login, keyboard or controller", function()
    boot(false, { color = "C351B4E4" })
    eq(dotColor(), string.format("%.2f %.2f %.2f %.2f", 0xC3 / 255, 0x51 / 255, 0xB4 / 255, 0xE4 / 255))
end)

test("the color: 32 bits RRGGBBAA from /gcc, six digits opaque, a wrong one changes nothing", function()
    boot(true, nil)
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("FF3030CC")
    eq(GamepadCrosshairCustomizerDB.color, "FF3030CC")
    eq(dotColor(), "1.00 0.19 0.19 0.80", "tinted at once")
    eq(game.printed[#game.printed]:find("FF3030CC", 1, true) ~= nil, true, "and says so")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("nonsense")
    eq(GamepadCrosshairCustomizerDB.color, "FF3030CC", "a wrong color changes nothing")
    eq(game.printed[#game.printed]:find("usage", 1, true) ~= nil, true, "and says how")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("#00ff00")
    eq(GamepadCrosshairCustomizerDB.color, "00FF00FF", "six digits: opaque")
end)

test("the swatch speaks AARRGGBB and sets the color only; the opacity is kept", function()
    boot(true, { color = "00FF0066" })
    local swatch = game.swatch
    eq(swatch.getValue(), "FF00FF00", "alpha FF, the color")
    swatch.setValue("ff0000ff")
    eq(GamepadCrosshairCustomizerDB.color, "0000FF66", "the picked color, the opacity kept")
    swatch.setValue("nonsense")
    eq(GamepadCrosshairCustomizerDB.color, "0000FF66", "a wrong value changes nothing")
    GamepadCrosshairCustomizer.SetOpacity(0.4)
    eq(GamepadCrosshairCustomizerDB.color, "0000FF66", "40% opacity")
    eq(dotColor(), "0.00 0.00 1.00 0.40")
end)

test("Enable off puts the dot's own color back, on brings yours back", function()
    boot(true, { color = "00FF00FF" })
    GamepadReticle.Icons.StandardIcon.color = { 0.9, 0.8, 0.7, 1 }   -- not what the addon saw at login
    setEnabled(false)
    eq(dotColor(), "1.00 1.00 1.00 1.00", "the color the dot had before the first tint")
    setEnabled(true)
    eq(dotColor(), "0.00 1.00 0.00 1.00", "and back")
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("FF0000FF")
    setEnabled(false)
    eq(GamepadCrosshairCustomizerDB.color, "FF0000FF", "off keeps your color for later")
    eq(dotColor(), "1.00 1.00 1.00 1.00", "and doesn't tint")
end)

test("controller: while the picker is open for the crosshair color, the sticks and D-pad drive it", function()
    boot(true, nil)
    local driver = GamepadCrosshairCustomizer.PickerSticks.driver
    local function step(seconds) driver.update(driver, seconds) end
    ColorPickerFrame:Show()
    eq(driver.shown, false, "a picker opened by something else (the chat settings): left to the game")
    eq(ColorPickerFrame.hasOpacity, nil, "and no opacity bar put on it")
    ColorPickerFrame:Hide()
    SlashCmdList.GAMEPADCROSSHAIRCUSTOMIZER("FFFFFF80")
    game.swatch.getValue()   -- the swatch reads the color as it opens the picker
    game.time = game.time + 0.1
    ColorPickerFrame:Show()
    eq(driver.shown, true, "opened for the crosshair color")
    eq(ColorPickerFrame.hasOpacity, true, "the opacity bar put on the picker")
    eq(game.picker.barShown, true)
    near(game.picker.alpha, 128 / 255, "at the crosshair's opacity")
    game.padUp = true; step(0.5)
    near(game.picker.alpha, 128 / 255 + 0.25, "D-pad up: more solid (0.5 a second)")
    eq(GamepadCrosshairCustomizerDB.color:sub(7, 8), string.format("%02X", math.floor((128 / 255 + 0.25) * 255 + 0.5)),
        "and the crosshair with it")
    game.padUp, game.padDown = false, true; step(10)
    near(game.picker.alpha, 0, "D-pad down: see-through, not past 0")
    game.padDown = false
    ColorPickerFrame.opacityFunc()   -- the mouse on the bar: the picker's own callback
    eq(GamepadCrosshairCustomizerDB.color:sub(7, 8), "00")
    game.cameraStickY = 1; step(0.5)
    near(game.picker.hsv[3], 0.8, "right stick up: brighter (0.6 a second)")
    eq(game.picker.hsv[1], 120, "the hue kept")
    game.cameraStickY = -1; step(5)
    near(game.picker.hsv[3], 0, "right stick down: darker, not past black")
    game.cameraStickY = 0.1; step(1)
    near(game.picker.hsv[3], 0, "inside the dead zone: nothing")
    game.cameraStickY = 0

    -- The left stick: the point on the wheel. Hue 0 sits at the point (-1, 0).
    game.picker.hsv = { 0, 0, 1 }   -- the middle: white
    game.moveStickX = -1; step(0.5)
    near(game.picker.hsv[2], 0.4, "left: out from the middle, saturation 0.4 (0.8 a second)")
    near(game.picker.hsv[1], 0, "toward hue 0")
    game.moveStickX, game.moveStickY = 0, -1; step(0.5)
    local x, y = GamepadCrosshairCustomizer.PickerSticks.WheelPoint(game.picker.hsv[1], game.picker.hsv[2])
    near(x, -0.4, "down: the point moves down"); near(y, -0.4)
    game.moveStickX, game.moveStickY = -1, 0; step(10)
    near(game.picker.hsv[2], 1, "never past the wheel's edge")
    near(game.picker.hsv[3], 1, "the brightness kept")
    game.moveStickX, game.moveStickY = 0.1, 0.1; local before = game.picker.hsv[1]; step(1)
    eq(game.picker.hsv[1], before, "inside the dead zone: nothing")
    game.moveStickX, game.moveStickY = 0, 0
    ColorPickerFrame:Hide()
    eq(driver.shown, false, "picker shut: nothing runs")
end)

test("keyboard: the picker gets the opacity bar but no stick driver", function()
    boot(false, nil)
    game.swatch.getValue()
    ColorPickerFrame:Show()
    eq(ColorPickerFrame.hasOpacity, true)
    eq(GamepadCrosshairCustomizer.PickerSticks.driver.shown, false)
end)

test("an addon of its own: needs no other addon, and the .toc loads its three files", function()
    local toc = readFile("GamepadCrosshairCustomizer.toc")
    eq(toc:find("Dependencies", 1, true), nil); eq(toc:find("OptionalDeps", 1, true), nil)
    eq(table.concat(tocFiles(), ","), "Color.lua,PickerSticks.lua,GamepadCrosshairCustomizer.lua")
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
