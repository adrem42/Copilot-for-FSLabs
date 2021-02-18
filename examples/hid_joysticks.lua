
-- Example usage of the `Joystick` library

FSL = require "FSL2Lua"
FSL:setPilot "CPT"

Joystick.printDeviceInfo() -- Print info on all devices

-- 0x06A3 is the vendor ID and 0x0C2D is the product ID
-- You can get the IDs from Joystick.printDeviceInfo()
-- or HidScanner.exe that comes with FSUIPC (it's in the Utils folder).
myJoy = Joystick.new(0x06A3, 0x0C2D)
anotherJoy = Joystick.new(0x06A3, 0x0763)

-- Print all button and axis activity
Joystick.logAllJoysticks()

-----------------------------------------
---- Buttons ----------------------------
-----------------------------------------

myJoy:onPress(1, print, "Hello " .. myJoy.info.product .. "!")

myJoy:onPress(9, 
  -- Bind.toggleButtons will keep the toggle states
  -- of the buttons in sync.
  Bind.toggleButtons(
    FSL.OVHD_AI_Eng_1_Anti_Ice_Button,
    FSL.OVHD_AI_Eng_2_Anti_Ice_Button
  )
)

myJoy:bindButton(8, FSL.CPT.PED_RADIO_NAV_Button)

myJoy:bindPush(1, FSL.CPT.GSLD_EFIS_Baro_Switch)
myJoy:bindPull(2, FSL.CPT.GSLD_EFIS_Baro_Switch)

myJoy:onPress(5, 
  FSL.OVHD_EXTLT_Land_L_Switch, "ON",
  FSL.OVHD_EXTLT_Land_R_Switch, "ON")

myJoy:onPress(6, 
  FSL.OVHD_EXTLT_Land_L_Switch, "RETR",
  FSL.OVHD_EXTLT_Land_R_Switch, "RETR")

myJoy:onPress   (2, FSL.PED_COMM_INT_RAD_Switch, "RAD")
myJoy:onRelease (2, FSL.PED_COMM_INT_RAD_Switch, "OFF")

-- 30 is the repeat interval in milliseconds
myJoy:onPressRepeat(4, 30, FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateLeft")
myJoy:onPressRepeat(3, 30, FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateRight")

-- Divide the knob in 5 steps and cycle back and forth
myJoy:onPress(1, Bind.cycleRotaryKnob(FSL.OVHD_INTLT_Integ_Lt_Knob, 5))

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

--- Anything involving A/C type-specific controls needs to be 
--- wrapped in A/C type checks:

if FSL:getAcType() == "A321" then
  myJoy:bindButton(7, FSL.OVHD_FUEL_CTR_TK_1_VALVE_Button)
  myJoy:bindButton(8, FSL.OVHD_CALLS_ALL_Button)
else
  myJoy:bindButton(7, FSL.OVHD_FUEL_CTR_TK_1_PUMP_Button)
end

------------------------------------------

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