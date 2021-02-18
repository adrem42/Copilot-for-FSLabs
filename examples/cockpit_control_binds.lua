-- Example usage of `FSL2Lua.Bind`

local FSL = require "FSL2Lua"
FSL:setPilot "CPT"

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
  -- Bind.toggleButtons will keep the toggle states
  -- of the buttons in sync.
  onPress = Bind.toggleButtons(
    FSL.OVHD_AI_Eng_1_Anti_Ice_Button,
    FSL.OVHD_AI_Eng_2_Anti_Ice_Button
  )
}

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

Bind {key = "\191", bindButton = FSL.GSLD_Chrono_Button}

Bind {key = "F1", onPress = {FSL.MIP_CHRONO_ELAPS_SEL_Switch, "RUN"}}
Bind {key = "F2", onPress = {FSL.MIP_CHRONO_ELAPS_SEL_Switch, "STP"}}

Bind {key = "Backspace", onPress = {ipc.control, 66807}}

Bind {
  btn = "C5", 
  onPress = {FSL.PED_COMM_INT_RAD_Switch, "RAD"}, 
  onRelease = {FSL.PED_COMM_INT_RAD_Switch, "OFF"}
}

Bind {btn = "C2", onPress = {FSL.PED_COMM_INT_RAD_Switch, "INT"}}
Bind {btn = "C3", onPress = {FSL.PED_COMM_INT_RAD_Switch, "OFF"}}
