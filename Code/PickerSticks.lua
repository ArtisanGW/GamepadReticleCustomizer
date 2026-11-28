-- The game's color picker (ColorPickerFrame) on a controller, while it's open for
-- this addon's color: a snippet to copy as is into an addon (DevTools/luaSnippets;
-- README.md there says how to use it).
--
-- Opened for an addon's setting, the picker's own stick bindings never work (the
-- game refuses them, while the same picker opened from the chat settings works).
-- So while it's open for our color, as the game's own bindings would:
--   the left stick moves the point on the color wheel (direction = hue, distance
--   from the middle = saturation; ColorPickerSoftCursor_OnUpdate's mapping);
--   the right stick's up and down change the brightness;
--   the D-pad's up and down change the opacity, on the picker's own opacity bar,
--   which the settings swatch doesn't ask for, so it's put on the picker here,
--   with the controller's D-pad up/down icon under it, pressed while held (the
--   game's own footer hint for it shows only when the picker opens with its
--   opacity: refreshing that footer from addon code would taint its bindings,
--   so the icon is ours, the game's art for the controller in use).
-- Nothing runs while the picker is shut, or open for anything else.
--
-- It knows nothing of the color it's for: PickerSticks.Watch(owner) takes an owner with
--   owner.OpenedThePicker() -- whether the picker now showing was opened for it
--   owner.Opacity()         -- its opacity, 0 to 1, for the opacity bar
--   owner.SetOpacity(alpha) -- the bar or the D-pad changed it
local _, addonTable = ...

local PickerSticks = {
    BRIGHTNESS_PER_SECOND = 0.6,   -- full stick: dark to bright in under two seconds
    WHEEL_PER_SECOND = 0.8,        -- full stick: the middle to the wheel's edge in about a second
    OPACITY_PER_SECOND = 0.5,      -- D-pad held: see-through to solid in two seconds (the game's: 0.01 per 0.02 s)
    STICK_DEAD_ZONE = 0.2,
    OPACITY_ICON_SIZE = 28,
    OPACITY_ICON_KEY = "DIRPADVERTICAL",   -- GAMEPAD_DPAD_VERTICAL (GamepadConstants.lua:14)
    ICON_NORMAL = 1, ICON_PRESSED = 3,     -- InputIconTextureState (InputIconTexture.lua:25-31)
}
addonTable.PickerSticks = PickerSticks

local function isControllerUIOn()
    return type(InputUtil) == "table" and type(InputUtil.IsGamepadUIEnabled) == "function"
        and InputUtil.IsGamepadUIEnabled() == true
end

local function mappedControllerState()
    local gamePad = _G.C_GamePad
    if type(gamePad) ~= "table" or type(gamePad.GetDeviceMappedState) ~= "function" then return nil end
    local succeeded, state = pcall(gamePad.GetDeviceMappedState)
    if not (succeeded and type(state) == "table") then return nil end
    return state, gamePad
end

-- A stick's x and y, -1 to 1: "Movement" (left) or "Camera" (right). 0, 0 without one.
function PickerSticks.StickPosition(configNameWanted)
    local state, gamePad = mappedControllerState()
    if not (state and type(state.sticks) == "table") then return 0, 0 end
    for stickIndex = 1, state.stickCount or #state.sticks do
        local configName = type(gamePad.StickIndexToConfigName) == "function"
            and gamePad.StickIndexToConfigName(stickIndex - 1) or nil   -- the game's function is 0 based
        local stick = state.sticks[stickIndex]
        if configName == configNameWanted and type(stick) == "table" then
            return tonumber(stick.x) or 0, tonumber(stick.y) or 0
        end
    end
    return 0, 0
end

-- Whether a controller button is held, by its binding name ("PADDUP", "PADDDOWN").
function PickerSticks.PadButtonDown(configNameWanted)
    local state, gamePad = mappedControllerState()
    if not (state and type(state.buttons) == "table" and type(gamePad.ButtonIndexToConfigName) == "function") then
        return false
    end
    for buttonIndex = 1, state.buttonCount or #state.buttons do
        if state.buttons[buttonIndex] and gamePad.ButtonIndexToConfigName(buttonIndex - 1) == configNameWanted then
            return true
        end
    end
    return false
end

-- The wheel's point for a hue (degrees) and saturation (0 to 1), and back:
-- hue = the point's angle + 180, saturation = its distance from the middle.
function PickerSticks.WheelPoint(hue, saturation)
    local angle = math.rad(hue - 180)
    return saturation * math.cos(angle), saturation * math.sin(angle)
end

function PickerSticks.WheelColor(x, y)
    local distance = math.sqrt(x * x + y * y)
    if distance > 1 then x, y, distance = x / distance, y / distance, 1 end
    local hue = math.deg(math.atan2(y, x)) + 180
    return hue % 360, distance
end

local owner        -- set by PickerSticks.Watch
local opacityIcon  -- our D-pad icon under the opacity bar, made the first time it's needed

-- The game's art for a controller key in a state, for the controller in use
-- (InputIconTextureSetUtility, forever branch InputIconTexture.lua:556-567): an
-- atlas name, or nil.
function PickerSticks.IconAtlas(key, state)
    local utility = rawget(_G, "InputIconTextureSetUtility")
    if type(utility) ~= "table" or type(utility.GetActiveInputIconButtonTextures) ~= "function" then return nil end
    local succeeded, textures = pcall(utility.GetActiveInputIconButtonTextures, key)
    local atlas = succeeded and type(textures) == "table" and textures[state] or nil
    return type(atlas) == "string" and atlas or nil
end

-- The icon as pressed (D-pad held) or not.
local function showIconPressed(pressed)
    if not (opacityIcon and opacityIcon:IsShown()) or opacityIcon.pressed == pressed then return end
    local atlas = PickerSticks.IconAtlas(PickerSticks.OPACITY_ICON_KEY,
        pressed and PickerSticks.ICON_PRESSED or PickerSticks.ICON_NORMAL)
    if atlas then opacityIcon:SetAtlas(atlas) end
    opacityIcon.pressed = pressed
end

local function colorSelectOf(picker)
    return type(picker) == "table" and picker.Content and picker.Content.ColorPicker
end

-- One frame of stick and D-pad input, applied to the picker's color and opacity.
local function moveWithSticks(colorSelect, elapsed)
    local hue, saturation, value = colorSelect:GetColorHSV()
    local newHue, newSaturation, newValue = hue, saturation, value
    local leftX, leftY = PickerSticks.StickPosition("Movement")
    if math.sqrt(leftX * leftX + leftY * leftY) >= PickerSticks.STICK_DEAD_ZONE then
        local x, y = PickerSticks.WheelPoint(hue, saturation)
        newHue, newSaturation = PickerSticks.WheelColor(x + leftX * PickerSticks.WHEEL_PER_SECOND * elapsed,
            y + leftY * PickerSticks.WHEEL_PER_SECOND * elapsed)
    end
    local _, rightY = PickerSticks.StickPosition("Camera")
    if math.abs(rightY) >= PickerSticks.STICK_DEAD_ZONE then
        newValue = math.max(0, math.min(1, value + rightY * PickerSticks.BRIGHTNESS_PER_SECOND * elapsed))
    end
    if newHue ~= hue or newSaturation ~= saturation or newValue ~= value then
        colorSelect:SetColorHSV(newHue, newSaturation, newValue)
    end
    local upHeld, downHeld = PickerSticks.PadButtonDown("PADDUP"), PickerSticks.PadButtonDown("PADDDOWN")
    showIconPressed(upHeld or downHeld)
    local opacityDirection = (upHeld and 1 or 0) - (downHeld and 1 or 0)
    if opacityDirection ~= 0 and type(colorSelect.GetColorAlpha) == "function" then
        local alpha = colorSelect:GetColorAlpha() or 1
        local newAlpha = math.max(0, math.min(1, alpha + opacityDirection * PickerSticks.OPACITY_PER_SECOND * elapsed))
        if newAlpha ~= alpha then
            colorSelect:SetColorAlpha(newAlpha)
            owner.SetOpacity(newAlpha)
        end
    end
end

local stickDriver = CreateFrame("Frame")
stickDriver:Hide()
stickDriver:SetScript("OnUpdate", function(self, elapsed)
    local picker = _G.ColorPickerFrame
    local colorSelect = colorSelectOf(picker)
    if not (colorSelect and picker:IsShown()) then return self:Hide() end
    moveWithSticks(colorSelect, elapsed)
end)
PickerSticks.driver = stickDriver

-- The picker's opacity bar, as the game's OnShow shows it when asked (hasOpacity),
-- on the owner's opacity. The next picker anyone opens sets these again.
function PickerSticks.AddOpacityBar(picker)
    local content = picker.Content
    local colorSelect = colorSelectOf(picker)
    if not colorSelect or type(colorSelect.SetColorAlpha) ~= "function" then return end
    local alpha = owner.Opacity() or 1
    picker.hasOpacity, picker.opacity = true, alpha
    picker.opacityFunc = function()
        if type(colorSelect.GetColorAlpha) == "function" then owner.SetOpacity(colorSelect:GetColorAlpha()) end
    end
    for _, part in ipairs({ colorSelect.Alpha, colorSelect.AlphaThumb, content.AlphaBackground }) do
        if type(part) == "table" and part.Show then part:Show() end
    end
    colorSelect:SetColorAlpha(alpha)
    if colorSelect.SetWidth then colorSelect:SetWidth(255) end   -- the game's widths with the bar
    if picker.SetWidth then picker:SetWidth(388) end
end

-- The D-pad up/down icon under the opacity bar, on a controller only.
function PickerSticks.ShowOpacityHint(picker)
    local colorSelect = colorSelectOf(picker)
    local bar = colorSelect and colorSelect.Alpha
    local atlas = PickerSticks.IconAtlas(PickerSticks.OPACITY_ICON_KEY, PickerSticks.ICON_NORMAL)
    if not (bar and atlas and type(picker.CreateTexture) == "function") then return end
    if not opacityIcon then
        opacityIcon = picker:CreateTexture(nil, "OVERLAY")
        opacityIcon:SetSize(PickerSticks.OPACITY_ICON_SIZE, PickerSticks.OPACITY_ICON_SIZE)
    end
    opacityIcon:SetAtlas(atlas)   -- each time: the controller may have changed
    opacityIcon.pressed = false
    opacityIcon:ClearAllPoints()
    opacityIcon:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    opacityIcon:Show()
end

function PickerSticks.HideOpacityHint()
    if opacityIcon then opacityIcon:Hide() end
end

-- Watches the game's picker (post-hooks only) for the given owner. Once.
function PickerSticks.Watch(pickerOwner)
    local picker = _G.ColorPickerFrame
    if owner or type(picker) ~= "table" or type(picker.HookScript) ~= "function" then return end
    owner = pickerOwner
    picker:HookScript("OnShow", function()
        local ours = owner.OpenedThePicker()
        if ours then PickerSticks.AddOpacityBar(picker) end
        if ours and isControllerUIOn() then
            stickDriver:Show()
            PickerSticks.ShowOpacityHint(picker)
        else
            stickDriver:Hide()
            PickerSticks.HideOpacityHint()
        end
    end)
    picker:HookScript("OnHide", function()
        stickDriver:Hide()
        PickerSticks.HideOpacityHint()
    end)
end
