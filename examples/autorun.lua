
FSL:setPilot "CPT"

------------------------------------------------------
-- Keyboard ------------------------------------------
------------------------------------------------------

--- Scroll down further for joystick button and axis bindings

Bind {key = "F5", onPress = {FSL.OVHD_EXTLT_Strobe_Switch, "ON"}}
Bind {key = "Ins", onPress = {FSL.OVHD_EXTLT_Strobe_Switch, "AUTO"}}
Bind {key = "Del", onPress = {FSL.OVHD_EXTLT_Strobe_Switch, "OFF"}}

Bind {key = "NumpadMinus", bindPush = FSL.CPT.GSLD_EFIS_Baro_Switch}
Bind {key = "NumpadPlus", bindPull = FSL.CPT.GSLD_EFIS_Baro_Switch}
Bind {key = "NumpadEnter", bindButton = FSL.MIP_ISIS_BARO_Button}

--- Anything involving A/C type-specific controls needs to be
--- wrapped in A/C type checks:

if FSL:getAcType() == "A321" then
  Bind {key = "F1", bindButton = FSL.OVHD_FUEL_CTR_TK_1_VALVE_Button}
  Bind {key = "F2", bindButton = FSL.OVHD_CALLS_ALL_Button}
else
  Bind {key = "F1", bindButton = FSL.OVHD_FUEL_CTR_TK_1_PUMP_Button}
end

Bind {
  key = "A",
  onPress = Bind.toggleButtons(
    FSL.OVHD_AI_Eng_1_Anti_Ice_Button,
    FSL.OVHD_AI_Eng_2_Anti_Ice_Button
  )
}

Bind {key = "F", onPress = Bind.cycleSwitch(FSL.OVHD_EXTLT_Strobe_Switch)}

Bind {
  key = "F6",
  onPress = {
    FSL.OVHD_EXTLT_Land_L_Switch, "ON",
    FSL.OVHD_EXTLT_Land_R_Switch, "ON"
  }
}

Bind {
  key = "Home",
  onPress = {
    FSL.OVHD_EXTLT_Land_L_Switch, "OFF",
    FSL.OVHD_EXTLT_Land_R_Switch, "OFF"
  }
}

Bind {
  key = "End",
  onPress = {
    FSL.OVHD_EXTLT_Land_L_Switch, "RETR",
    FSL.OVHD_EXTLT_Land_R_Switch, "RETR"
  }
}

Bind {key = "PageUp", onPress = {FSL.OVHD_EXTLT_Nose_Switch, "TAXI"}}
Bind {key = "PageDown", onPress = {FSL.OVHD_EXTLT_Nose_Switch, "OFF"}}

Bind {key = "NumpadDiv", onPress = {FSL.OVHD_INTLT_Dome_Switch, "BRT"}}

Bind {key = "F1", onPress = {FSL.MIP_CHRONO_ELAPS_SEL_Switch, "RUN"}}
Bind {key = "F2", onPress = {FSL.MIP_CHRONO_ELAPS_SEL_Switch, "STP"}}

------------------------------------------------------
-- Joysticks -----------------------------------------
------------------------------------------------------

-- 0x06A3 is the vendor ID and 0x0C2D is the product ID
-- You can get the IDs from Joystick.printDeviceInfo()
-- or HidScanner.exe that comes with FSUIPC (it's in the Utils folder).
myJoy = Joystick.new(0x06A3, 0x0C2D)
anotherJoy = Joystick.new(0x06A3, 0x0763)

-- Print all button and axis activity
Joystick.logAllJoysticks()

----------------------------------------
---- Buttons ---------------------------
----------------------------------------

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

myJoy:onPressRepeat(4, 30, FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateLeft")
myJoy:onPressRepeat(3, 30, FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateRight")

myJoy:onPress(1, Bind.cycleRotaryKnob(FSL.OVHD_INTLT_Integ_Lt_Knob, 5))

myJoy:onPress(9,
  Bind.toggleButtons(
    FSL.OVHD_AI_Eng_1_Anti_Ice_Button,
    FSL.OVHD_AI_Eng_2_Anti_Ice_Button
  )
)

-----------------------------------------
---- Axes -------------------------------
-----------------------------------------

myJoy:onAxis("Y", FSL.GSLD_FCU_DimLt_Knob)
myJoy:onAxis("Z", FSL.CPT.PED_COMM_VHF1_Knob):props():invert()
