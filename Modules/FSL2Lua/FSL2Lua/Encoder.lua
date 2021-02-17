local Bind = require "FSL2Lua.FSL2Lua.Bind"

Encoder = {
  _onCW   = function () end,
  _onCCW  = function () end,
  DIR_CW = 0,
  DIR_CCW = 1
}
if Joystick then
  getmetatable(Joystick).gottaGoFast = function(howFast, ...)

    local func = Bind:makeSingleFunc {...}

    local prevTimestamp = 0

    local callback = function(_, _, timestamp)
      local diff = timestamp - prevTimestamp
      prevTimestamp = timestamp
      local numTicks = howFast(diff)
      for _ = 1, numTicks do
        func()
      end
    end

    return callback, Joystick.sendEventDetails
  end
end

function Encoder.new(joy, data)

  if type(data[1]) ~= "number" or type(data[2]) ~= "number" then
    error("Specify two button numbers for the encoder", 2)
  end

  local DPC = data.detentsPerCycle

  if DPC == nil then
    error("Missing detentsPerCycle argument", 2)
  end

  if DPC ~= 1 and DPC ~= 2 and DPC ~= 4 then
    error("detentsPerCycle must be either 1, 2 or 4", 2)
  end

  local shift = 0

  if data.shift == true then
    if DPC == 1 then shift = 2
    elseif DPC == 2 then shift = 1 end
  end

  local e = {
    _pinA = data[1],
    _pinB = data[2],
    _prevStateA = false,
    _prevStateB = false,
    _detentRatio = 4 / DPC,
    _count = 0,
    _shift = shift,
    _direction = Encoder.DIR_CW
  }

  local function callback(button, state, timestamp)
    e:_onPinEvent(button, state, timestamp)
  end

  joy:onPress   (data[1], callback, Joystick.sendEventDetails)
  joy:onPress   (data[2], callback, Joystick.sendEventDetails)
  joy:onRelease (data[1], callback, Joystick.sendEventDetails)
  joy:onRelease (data[2], callback, Joystick.sendEventDetails)

  Encoder.__index = Encoder
  return setmetatable(e, Encoder)
end

function Encoder:setTickCalculator(tickCalculator)
  self._calculateTicks = tickCalculator
  return self
end

function Encoder:_makeCallback(...)
  if not self._calculateTicks then
    local func = Bind:makeSingleFunc {...}
    return function() func() end
  end
  return Joystick.gottaGoFast(self._calculateTicks, ...)
end

function Encoder:onCW(...)
  self._onCW = self:_makeCallback(...)
  return self
end

function Encoder:onCCW(...)
  self._onCCW = self:_makeCallback(...)
  return self
end

function Encoder:_calculateDirection(this, thisPrev, other)
  if this and not thisPrev then
    return other and self.DIR_CCW or self.DIR_CW
  else
    return other and self.DIR_CW or self.DIR_CCW
  end
end

function Encoder:_onPinEvent(pin, state, timestamp)
  state = state == 1
  local direction, other
  if pin == self._pinA then
    other = self._prevStateB
    direction = self:_calculateDirection(state, self._prevStateA, other)
    self._prevStateA = state
  else
    other = self._prevStateA
    direction = self:_calculateDirection(state, self._prevStateB, not other)
    self._prevStateB = state
  end
  if not state and not other then
    self._count = 0
  else
    self._count = (self._count + 1) % 4
  end
  self._direction = direction
  if (self._count + self._shift) % self._detentRatio == 0 then
    if direction == self.DIR_CW then
      self._onCW(nil, nil, timestamp)
    else
      self._onCCW(nil, nil, timestamp)
    end
  end
end

return Encoder