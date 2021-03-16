
copilot.AFTER_LANDING_TRIGGER_VOICE = 1
copilot.AFTER_LANDING_TRIGGER_DISARM_SPOILERS = 2
copilot.TAKEOFF_PACKS_TURN_OFF = 0
copilot.TAKEOFF_PACKS_LEAVE_ALONE = 1
local UserOptions = {TRUE = 1, FALSE = 0, ENABLED = 1, DISABLED = 0}
copilot.UserOptions = UserOptions

return {
  {
    title = "General",
    keys = {
      {
        name = "enable", 
        default = UserOptions.TRUE, 
        comment = "Global enable",
        type = "bool"
      },
      {
        name = "http_port", 
        default = 8080,
        comment = "The port of the web MCDU - leave it at default unless you changed it in the FSLabs settings", 
        type = "string"
      },
      {
        name = "PM_seat", 
        default = "right", 
        comment = "Where the Pilot Monitoring sits in the cockpit - left or right", 
        type = "enum", 
        values = {"left", "right"}, 
        required = true
      },
      {
        name = "debugger", 
        hidden = true, 
        type = "bool"
      },
      {
        name = "debugger_bind", 
        hidden = true, 
        type = "string"
      },
      {
        name = "button_sleep_mult",
        default = 1,
        comment = "Multiplier for how long to hold buttons depressed. Try increasing this value in steps of 1 if you notice button clicks not registering.",
        type = "number"
      }
    }
  },
  {
    title = "Voice_control",
    keys = {
      {
        name = "enable",
        default = UserOptions.TRUE, 
        type = "bool"
      }
    }
  },
  {
    title = "Callouts",
    keys = {
      {
        name = "sound_set", 
        default = "Hannes", 
        type = "string"
      },
      {
        name = "enable", 
        default = UserOptions.TRUE, 
        type = "bool"
      },
      {
        name = "volume", 
        default = 60, 
        type = "int",
        comment = "This sets the maximum volume from 0-100. You can also adjust the volume with the INT volume knob in the cockpit",
      },
      {
        name = "device_id", 
        default = -1, 
        comment = "-1 is the default device", 
        type = "int"
      },
      {
        name = "PM_announces_flightcontrol_check", 
        default = 1, 
        type = "bool"
      },
      {
        name = "PM_announces_brake_check", 
        default = 1, 
        type = "bool"
      }
    }
  },
  {
    title = "Actions",
    keys = {
      {
        name = "enable", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "PM_clears_scratchpad", 
        default = UserOptions.TRUE,
        comment = "If enabled, PM will clear his scratchpad during the preflight FMGC check.",
        type = "bool"
      },
      {
        name = "preflight", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "after_start", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "during_taxi", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "lineup", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "takeoff_sequence", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "after_takeoff", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "ten_thousand_dep", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "ten_thousand_arr", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "after_landing", 
        default = UserOptions.ENABLED, 
        type = "bool"
      },
      {
        name = "after_landing_trigger", 
        default = copilot.AFTER_LANDING_TRIGGER_VOICE, 
        comment = "explained in the manual", 
        type = "enum", 
        values = {copilot.AFTER_LANDING_TRIGGER_VOICE, copilot.AFTER_LANDING_TRIGGER_DISARM_SPOILERS}
      },
      {
        name = "FDs_off_after_landing", 
        default = UserOptions.TRUE, 
        comment = "explained in the manual", 
        type = "bool"
      },
      {
        name = "packs_on_takeoff", 
        default = copilot.TAKEOFF_PACKS_TURN_OFF,
        comment = "If you make an ATSU performance request, whatever you enter there will override this option",
        type = "enum", 
        values = {copilot.TAKEOFF_PACKS_TURN_OFF, copilot.TAKEOFF_PACKS_LEAVE_ALONE}
      },
      {
        name = "pack2_off_after_landing", 
        default = UserOptions.FALSE, 
        type = "bool"
      }
    }
  },
  {
    title = "Failures",
    comment = {
      "If enable is set to 1, the script will set up random failures in the MCDU when the flight is loaded",
      "By default, the rate of each failure is set to 1 / 10000 hours",
      "You can change the global rate and the rate for each individual failure below"
    },    
    keys = {
      {
        name = "enable", 
        default = UserOptions.FALSE, 
        type = "bool"
      },
      {
        name = "global_rate", 
        default = 1 / 10000, 
        type = "number"
      },
      {
        name = "per_airframe", 
        default = UserOptions.TRUE, 
        comment = "track failures separately for each airframe - 1 or 0",
        type = "bool"
      }
    }
  }
}