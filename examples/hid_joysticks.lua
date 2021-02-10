
-- Example usage of the `Joystick` library

FSL = require "FSL2Lua"
FSL:setPilot "CPT"

Joystick.printDeviceInfo() -- Print info on all devices in the FSUIPC log

-- 0x06A3 is the vendor ID and 0x0C2D is the product ID
-- You can get the IDs from Joystick.printDeviceInfo()
-- or HidScanner.exe that comes with FSUIPC (it's in the Utils folder).
myJoy = Joystick.new(0x06A3, 0x0C2D)
anotherJoy = Joystick.new(0x06A3, 0x0763)

-- Print all button and axis activity in the FSUIPC log
Joystick.logAllJoysticks()

-----------------------------------------
---- Buttons ----------------------------
-----------------------------------------

myJoy:onPress(1, print, "Hello " .. myJoy.info.product .. "!")

-- "ON" and "RETR" will be passed as arguments to these @{FSL2Lua.Switch.__call|callbacks}.
myJoy:onPress(5, 
  FSL.OVHD_EXTLT_Land_L_Switch, "ON",
  FSL.OVHD_EXTLT_Land_R_Switch, "ON")

myJoy:onPress(6, 
  FSL.OVHD_EXTLT_Land_L_Switch, "RETR",
  FSL.OVHD_EXTLT_Land_R_Switch, "RETR")

myJoy:onPress   (2, FSL.PED_COMM_INT_RAD_Switch, "RAD")
myJoy:onRelease (2, FSL.PED_COMM_INT_RAD_Switch, "OFF")

-- @{FSL2Lua.KnobWithoutPositions.rotateLeft|rotateLeft} and @{FSL2Lua.KnobWithoutPositions.rotateRight|rotateRight} are method names
-- 30 is the repeat interval in milliseconds
myJoy:onPressRepeat(4, 30, FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateLeft")
myJoy:onPressRepeat(3, 30, FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateRight")

-- Divide the knob in 5 steps and cycle back and forth
-- This a shorter version of:
-- myJoy:onPress(0, function() FSL.OVHD_INTLT_Integ_Lt_Knob:cycle(5) end)
myJoy:onPress(1, FSL.OVHD_INTLT_Integ_Lt_Knob, "cycle", 5)

myJoy:onPress(8, 
  FSL.CPT.PED_RADIO_NAV_Guard, "lift", 
  FSL.CPT.PED_RADIO_NAV_Button, "macro", "leftPress")

myJoy:onRelease(8, 
  FSL.CPT.PED_RADIO_NAV_Button, "macro", "leftRelease",
  FSL.CPT.PED_RADIO_NAV_Guard, "close")

-----------------------------------------
---- Encoders ---------------------------
-----------------------------------------

--[[ 
  This function takes the time in milliseconds
  that elapsed between the current and previous
  encoder ticks for the current direction and 
  returns how many times the encoder callback 
  should be invoked for the current tick.

  If no such function is passed to setTickCalculator,
  the callbacks will be invoked once per tick.
]]
function calculateKnobTicks(diff)
  if diff < 30 then return 10 end
  if diff < 50 then return 5 end
  return 1
end

myJoy:makeEncoder { 8, 9, detentsPerCycle = 4 }
  :setTickCalculator(calculateKnobTicks)
  :onCW(FSL.GSLD_FCU_HDG_Knob, "rotateRight")
  :onCCW(FSL.GSLD_FCU_HDG_Knob, "rotateLeft")

-----------------------------------------
---- Axes -------------------------------
-----------------------------------------

myJoy:onAxis("Y", FSL.GSLD_FCU_DimLt_Knob)

-- Invert the axis for this callback
myJoy:onAxis("Z", FSL.CPT.PED_COMM_VHF1_Knob):props():invert()

-----------------------------------------

-- Start reading the data
Joystick.read()

--[[

Joystick.read() never returns, so if you need to do 
other things in the same script, call Joystick.peek()
in a loop or timer instead:

while true do
  ipc.sleep(0)
  Joystick.peek()
  print "doing stuff"
end

]]