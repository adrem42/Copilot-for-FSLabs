
local readLvar = ipc.readLvar

local FlightControlCheck = {
  ERROR_PM_CHECK_TIMEOUT = {},
  MODE_ACTIVE_IMMEDIATE = {},
  MODE_ACTIVE_AFTER_FIRST_CHECK = {}
}
setmetatable(FlightControlCheck, FlightControlCheck)
local axes

local ecpButtons = table.map({
  "ENG", "BLEED", "PRESS", "ELEC", "HYD", "FUEL", 
  "APU", "COND", "DOOR", "WHEEL", "STS"
}, function(page) 
  return FSL["PED_ECP_" .. page .. "_Button"]
end)

local function confirmFctlEcamPage()
  if FSL.PED_ECP_FCTL_Button:isLit() then return end
  for _, butt in ipairs(ecpButtons) do
    if butt:isLit() then 
      copilot.suspend(1000, 2000)
      butt:pressIfLit() 
    end
  end
end

local LVAR_ELEVATOR_LEFT = "FSLA320_elevator_l"
local LVAR_ELEVATOR_RIGHT = "FSLA320_elevator_r"
local LVAR_AILERON_LEFT = "FSLA320_aileron_l"
local LVAR_AILERON_RIGHT = "FSLA320_aileron_r"
local LVAR_RUDDER = "FSLA320_rudder"

local DELAY_STICK, DELAY_RUDDER = 700, 400

local AILERON_TOLERANCE = 300
local ELEVATOR_TOLERANCE = 200
local RUDDER_TOLERANCE = 100

local RUDDER_TRAVEL_FULL_LEFT, RUDER_TRAVEL_FULL_RIGHT

if FSL:getAcType() == "A319" then
  RUDDER_TRAVEL_FULL_LEFT = 1243
  RUDER_TRAVEL_FULL_RIGHT = 2743
else
  RUDDER_TRAVEL_FULL_LEFT = 1499
  RUDER_TRAVEL_FULL_RIGHT = 3000
end

local sidestick = require "copilot.Sidestick"

function FlightControlCheck:new(mode)
  self.__index = self
  mode = mode or self.MODE_ACTIVE_IMMEDIATE
  return setmetatable({
    axes = axes(),
    isActive = mode == self.MODE_ACTIVE_IMMEDIATE,
    timeLastAction = ipc.elapsedtime()
  }, self)
end

function FlightControlCheck:onChecked(calloutFile, delay)
  confirmFctlEcamPage() 
  copilot.playCallout(calloutFile, plusminus(delay))
  self.timeLastAction = ipc.elapsedtime()
end

function FlightControlCheck:checkAxisPart(axisPart, axis)
  if self[axisPart.name](self) then
    self:onChecked(axisPart.callout, axis.delay)
    axisPart.checked = true
    axis.checkInProgress = true
    self.isActive = true
    return true
  end
end

function FlightControlCheck:checkAxis(axis)
  if not axis[1].checked or not axis[2].checked then
    if not axis[1].checked then
      self:checkAxisPart(axis[1], axis)
    end
    if not axis[2].checked then
      self:checkAxisPart(axis[2], axis)
    end
    return false
  end
  if self:checkAxisPart(axis.neutral, axis) then
    axis.checked = true
    axis.checkInProgress = false
    return true
  end
end

function FlightControlCheck:pfSideCheck()
  local ail, elev = self.axes.ailerons, self.axes.elevator
  if not elev.checked or not ail.checked then
    if not ail.checkInProgress and not elev.checked then
      self:checkAxis(elev)
    end
    if not elev.checkInProgress and not ail.checked then
      self:checkAxis(ail)
    end
  else
    return self:checkAxis(self.axes.rudder)
  end
end

function FlightControlCheck:__call()
  repeat 
    copilot.suspend(100)
    confirmFctlEcamPage()
    if self.isActive and ipc.elapsedtime() - self.timeLastAction > 10000 then
      return false, "timeout"
    end
  until self:pfSideCheck()
  copilot.suspend(2000, 5000)
  local ok, err = pcall(self.pmSideCheck, self)
  if not ok then
    sidestick.move {x = 0, y = 0}
    if err == self.ERROR_PM_CHECK_TIMEOUT then
      return false, self.ERROR_PM_CHECK_TIMEOUT
    else
      error(err)
    end
  end
  return true
end

function FlightControlCheck:pmSideCheck()
  self:pmTestSidestickAxis("y", "fullUp", "fullDown")
  self:pmTestSidestickAxis("x", "fullRight", "fullLeft")
end

function FlightControlCheck:pmTestSidestickAxis(axis, first, second)
  local function move(to, check)
    sidestick.move {[axis] = to}
    if not checkWithTimeout(5000, function()
      copilot.suspend(100)
      confirmFctlEcamPage()
      return self[check](self) 
    end) then 
      error(self.ERROR_PM_CHECK_TIMEOUT) 
    end
    copilot.suspend(700, 1200)
  end
  move(1, first)
  move(-1, second)
  move(0, "stickNeutral")
end

local function flapsRetracted()
  return readLvar "FSLA320_flap_l_1" == 0
end

function FlightControlCheck:fullLeft()
  local lvarVal = readLvar(LVAR_AILERON_LEFT)
  local x = flapsRetracted() and 1499 or 1199
  return lvarVal <= x and x - lvarVal < AILERON_TOLERANCE
end

function FlightControlCheck:fullRight()
  local lvarVal = readLvar(LVAR_AILERON_RIGHT)
  local x = flapsRetracted() and 3000 or 2700
  return x - lvarVal < AILERON_TOLERANCE
end

local function fullUp(lvar)
  local lvarVal = readLvar(lvar)
  return lvarVal <= 1499 and 1499 - lvarVal < ELEVATOR_TOLERANCE
end

function FlightControlCheck:fullUp()
  return fullUp(LVAR_ELEVATOR_LEFT) and fullUp(LVAR_ELEVATOR_RIGHT)
end

local function fullDown(lvar)
  return 3000 - readLvar(lvar) < ELEVATOR_TOLERANCE
end

function FlightControlCheck:fullDown()
  return fullDown(LVAR_ELEVATOR_LEFT) and fullDown(LVAR_ELEVATOR_RIGHT)
end

function FlightControlCheck:fullLeftRud()
  local lvarVal = readLvar(LVAR_RUDDER)
  if lvarVal > RUDDER_TRAVEL_FULL_LEFT then return false end
  return RUDDER_TRAVEL_FULL_LEFT - lvarVal < RUDDER_TOLERANCE
end

function FlightControlCheck:fullRightRud()
  return RUDER_TRAVEL_FULL_RIGHT - readLvar(LVAR_RUDDER) < RUDDER_TOLERANCE
end

local function _aileronNeutralFlapsRetracted(lvar)
  local lvarVal = readLvar(lvar)
  local x = 1500
  if lvarVal < AILERON_TOLERANCE then return true end
  return lvarVal >= x and lvarVal - x < AILERON_TOLERANCE
end

local function aileronNeutralFlapsRetracted()
  return _aileronNeutralFlapsRetracted(LVAR_AILERON_LEFT) and _aileronNeutralFlapsRetracted(LVAR_AILERON_RIGHT)
end

local function _aileronNeutralFlapsExtended(lvar, x)
  return math.abs(readLvar(lvar) - x) < AILERON_TOLERANCE
end

local function aileronNeutralFlapsExtended()
  return _aileronNeutralFlapsExtended(LVAR_AILERON_LEFT, 1980) and _aileronNeutralFlapsExtended(LVAR_AILERON_RIGHT, 480)
end

function FlightControlCheck:aileronNeutral()
  if flapsRetracted() then
    return aileronNeutralFlapsRetracted()
  else
    return aileronNeutralFlapsExtended()
  end
end

local function elevatorNeutral(lvar)
  local lvarVal = readLvar(lvar)
  local x = 1500
  if lvarVal < ELEVATOR_TOLERANCE then return true end
  return lvarVal >= x and lvarVal - x < ELEVATOR_TOLERANCE
end

function FlightControlCheck:elevatorNeutral()
  return elevatorNeutral(LVAR_ELEVATOR_LEFT) and elevatorNeutral(LVAR_ELEVATOR_RIGHT)
end

function FlightControlCheck:stickNeutral()
  return self:aileronNeutral() and self:elevatorNeutral()
end

function FlightControlCheck:rudNeutral()
  local lvarVal = readLvar "FSLA320_rudder"
  local x = 1500
  if lvarVal < RUDDER_TOLERANCE then return true end
  return lvarVal >= x and lvarVal - x < RUDDER_TOLERANCE
end

function axes()  
  return {
    ailerons = {
      delay = DELAY_STICK,
      [1] = {name = "fullLeft", callout = "fullLeft_1"},
      [2] = {name = "fullRight", callout = "fullRight_1"},
      neutral = {name = "stickNeutral", callout = "neutral_1"}
    },
    elevator = {
      delay = DELAY_STICK,
      [1] = {name = "fullUp", callout = "fullUp"},
      [2] = {name = "fullDown", callout = "fullDown"},
      neutral = {name = "stickNeutral", callout = "neutral_2"}
    },
    rudder = {
      delay = DELAY_RUDDER,
      [1] = {name = "fullLeftRud", callout = "fullLeft_2"},
      [2] = {name = "fullRightRud", callout = "fullRight_2"},
      neutral = {name = "rudNeutral", callout = "neutral_3"}
    }
  }
end

return FlightControlCheck