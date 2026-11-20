-- The game's color picker (ColorPickerFrame) on a controller, while it's open for
-- this addon's color.
--
-- Opened for an addon's setting, the picker's own stick bindings never work (the
-- game refuses them: seen in game, while the same picker opened from the chat
-- settings works). So while it's open for our color, as the game's own bindings would:
--   the left stick moves the point on the color wheel (direction = hue, distance
--   from the middle = saturation; ColorPickerSoftCursor_OnUpdate's mapping);
--   the right stick's up and down change the brightness;
--   the D-pad's up and down change the opacity, on the picker's own opacity bar,
--   which the settings swatch doesn't ask for, so it's put on the picker here.
-- Nothing runs while the picker is shut, or open for anything else.
--
-- It knows nothing of the reticle: PickerSticks.Watch(owner) takes an owner with
--   owner.OpenedThePicker() -- whether the picker now showing was opened for it
--   owner.Opacity()         -- its opacity, 0 to 1, for the opacity bar
--   owner.SetOpacity(alpha) -- the bar or the D-pad changed it
local _, addon = ...

local PickerSticks = {
    BRIGHTNESS_PER_SECOND = 0.6,   -- full stick: dark to bright in under two seconds
    WHEEL_PER_SECOND = 0.8,        -- full stick: the middle to the wheel's edge in about a second
    OPACITY_PER_SECOND = 0.5,      -- D-pad held: see-through to solid in two seconds (the game's: 0.01 per 0.02 s)
    STICK_DEAD_ZONE = 0.2,
}
addon.PickerSticks = PickerSticks

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

local owner   -- set by PickerSticks.Watch

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
    local opacityDirection = (PickerSticks.PadButtonDown("PADDUP") and 1 or 0)
        - (PickerSticks.PadButtonDown("PADDDOWN") and 1 or 0)
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
PickerSticks.driver = stickDriver   -- for the tests

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

-- Watches the game's picker (post-hooks only) for the given owner. Once.
function PickerSticks.Watch(pickerOwner)
    local picker = _G.ColorPickerFrame
    if owner or type(picker) ~= "table" or type(picker.HookScript) ~= "function" then return end
    owner = pickerOwner
    picker:HookScript("OnShow", function()
        local ours = owner.OpenedThePicker()
        if ours then PickerSticks.AddOpacityBar(picker) end
        if ours and isControllerUIOn() then stickDriver:Show() else stickDriver:Hide() end
    end)
    picker:HookScript("OnHide", function() stickDriver:Hide() end)
end
