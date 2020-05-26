--- See @{FSL2Lua.Bind} for details.

local FSL = require "FSL2Lua"
FSL:setPilot(1)

Bind {key = "F5", onPress = {FSL.OVHD_EXTLT_Strobe_Switch, "ON"}}
Bind {key = "Ins", onPress = {FSL.OVHD_EXTLT_Strobe_Switch, "AUTO"}}
Bind {key = "Del", onPress = {FSL.OVHD_EXTLT_Strobe_Switch, "OFF"}}

Bind {key = "NumpadMinus", onPress = {FSL.GSLD_EFIS_Baro_Switch, "push"}}
Bind {key = "NumpadPlus", onPress = {FSL.GSLD_EFIS_Baro_Switch, "pull"}}
Bind {key = "NumpadEnter", onPress = FSL.MIP_ISIS_BARO_Button}

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

Bind {key = "\191", onPress = FSL.GSLD_Chrono_Button}

Bind {key = "F1", onPress = {FSL.MIP_CHRONO_ELAPS_SEL_Switch, "RUN"}}
Bind {key = "F2", onPress = {FSL.MIP_CHRONO_ELAPS_SEL_Switch, "STP"}}

-- UGCX menu toggle
Bind {key = "Backspace", onPress = function () ipc.control(66807) end}

Bind {
  btn = "C5", 
  onPress = {FSL.PED_COMM_INT_RAD_Switch, "RAD"}, 
  onRelease = {FSL.PED_COMM_INT_RAD_Switch, "OFF"}
}

Bind {btn = "C2", onPress = {FSL.PED_COMM_INT_RAD_Switch, "INT"}}
Bind {btn = "C3", onPress = {FSL.PED_COMM_INT_RAD_Switch, "OFF"}}
