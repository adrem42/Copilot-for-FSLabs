
local util = require "FSL2Lua.FSL2Lua.util"
local Switch = require "FSL2Lua.FSL2Lua.Switch"
local J = {}

function J.printDeviceInfo()
  print "------------------------------------"
  print "-------  HID device info  ----------"
  print "------------------------------------"
  for _, device in ipairs(Joystick.enumerateDevices()) do
    print("Manufacturer: " .. device.manufacturer)
    print("Product: " .. device.product)
    print(string.format("Vendor ID: 0x%04X", device.vendorId))
    print(string.format("Product ID: 0x%04X", device.productId))
    print "------------------------------------"
  end
end

local function parseAxisArgs(...)
  if select("#", ...) == 2 then
    return select(...)
  else
    return 1, ...
  end
end

function J.signedAxis(...)
  local max, callback = parseAxisArgs(...)
  local mult = 1 / 50 * max
  return function(value)
    callback((value - 50) * mult)
  end
end

function J.unsignedAxis(...)
  local max, callback = parseAxisArgs(...)
  local mult = max / 100
  return function(value)
    callback(value * mult)
  end
end

function J.signedSimAxis(eventID)
  return J.signedAxis(0x4000, function(value)
    ipc.control(eventID, value)
  end)
end 

function J.unsignedSimAxis(eventID)
  return J.unsignedAxis(0x4000, function(value)
    ipc.control(eventID, value)
  end)
end

local BUTTON_STATE = {
  UNKNOWN = 0,
  DEPRESSED = 1,
  RELEASED = 2
}

function J:bindSwitch(switch, posMap)

  util.checkType(switch, Switch, "Switch", 2)
  local buttons, positions = {}, {}
  local numButtons = 0
  local numKnownButtonStates = 0

  local recheckRelease
  local numPressedButtons = 0

  local function onButton(buttonNum, action)
    local state = BUTTON_STATE[action == Joystick.BUTTON_EVENT_PRESS and "DEPRESSED" or "RELEASED"]
    local button = buttons[buttonNum]
    local prevState = button.state
    button.state = state
    if numKnownButtonStates < numButtons then
      numKnownButtonStates = numKnownButtonStates + 1
      if action == Joystick.BUTTON_EVENT_RELEASE and prevState == BUTTON_STATE.UNKNOWN then
        if button[BUTTON_STATE.RELEASED] then
          recheckRelease = buttonNum
        end
      end
      if numKnownButtonStates == numButtons then
        for _, b in pairs(buttons) do
          if b.state == BUTTON_STATE.DEPRESSED then
            numPressedButtons = numPressedButtons + 1
          end
        end
      end
      if recheckRelease and numKnownButtonStates == numButtons then
        local b = recheckRelease
        recheckRelease = nil
        numPressedButtons = numPressedButtons + 1
        onButton(b, Joystick.BUTTON_EVENT_RELEASE)
      elseif numKnownButtonStates < numButtons then
        return
      end
    else
      numPressedButtons = numPressedButtons + (button.state == BUTTON_STATE.DEPRESSED and 1 or -1)
    end
  
    local posIdx = button[state]
    if not posIdx then return end
    local pos = positions[posIdx]
    if state == BUTTON_STATE.RELEASED then
      if pos.button then return end
      if numPressedButtons ~= 0 then 
        return 
      end
    end
    switch(pos.label)
  end

  for _, pos in pairsByKeys(switch.LVarToPosn) do
    local button = posMap[pos]
    posMap[pos] = nil
    positions[#positions+1] = {label = pos, button = button}
  end

  for pos in pairs(posMap) do
    error(("Invalid position for switch '%s': '%s'"):format(switch.name, pos), 2)
  end

  local function initButton(button, buttonState, posIdx)
    buttons[button] = buttons[button] or {state = BUTTON_STATE.UNKNOWN}
    buttons[button][buttonState] = posIdx
  end

  local function considerOnRelease(posIdx, button)
    local pos = positions[posIdx]
    if pos and not pos.button then
      initButton(button, BUTTON_STATE.RELEASED, posIdx)
      return true
    end
    return false
  end

  for i, pos in ipairs(positions) do
    if pos.button then
      if buttons[pos.button] then 
        error("Two different assignments for button " .. pos.button, 2)
      end
      numButtons = numButtons + 1
      local button = pos.button
      initButton(button, BUTTON_STATE.DEPRESSED, i)
      self:setButtonStateUnknown(button)
      self:onPress(button, onButton, Joystick.sendEventDetails)
      self:onRelease(button, onButton, Joystick.sendEventDetails)
      local isReleaseButton = considerOnRelease(i - 1, button)
      if considerOnRelease(i + 1, button) and isReleaseButton then
        error("OFF-ON-OFF sequence", 2)
      end
    end
  end

end

return J