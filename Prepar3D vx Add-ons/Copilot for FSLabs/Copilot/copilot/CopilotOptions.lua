local UserOptions = copilot.UserOptions

copilot.LINEUP_TRIGGER_VOICE = 1
copilot.LINEUP_TRIGGER_SEAT_BELTS_SWITCH = 2

copilot.AFTER_LANDING_TRIGGER_VOICE = 1
copilot.AFTER_LANDING_TRIGGER_DISARM_SPOILERS = 2

copilot.TAKEOFF_PACKS_TURN_OFF = 0
copilot.TAKEOFF_PACKS_LEAVE_ALONE = 1

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
        hidden = true,
        type = "int"
      },
      {
        name = "con_log_level",
        type = "enum",
        values = {0, 1, 2, 3, 4, 5, 6},
        default = 2,
        hidden = true
      },
      {
        name = "PM_seat", 
        type = "enum", 
        values = {"left", "right", 1, 2}, 
        required = true,
        hidden = true
      },
      {
        name = "PF_seat", 
        type = "enum", 
        values = {"left", "right", 1, 2}, 
        required = true,
        hidden = true
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
        default = nil,
        type = "number",
        hidden = true
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
      },
      {
        name = "device", 
        default = nil, 
        comment = "Leave blank for default device. The list of devices is at the top of the log file.", 
        type = "string"
      },
      {
        name = "confidence_baseline",
        default = 0.93,
        comment = "Baseline confidence threshold for the default voice commands. Some voice commands will have a confidence above or below this value.",
        type = "number"
      },
      {
        name = "confidence_override",
        default = nil,
        comment = "Hard confidence threshold for the default voice commands. If set, ALL default voice commands will have exactly this confidence value.",
        type = "number"
      },
      {
        name = "mute_on_startup",
        default = UserOptions.FALSE,
        type = "bool"
      }
    }
  },
  {
    title = "Voice_commands",
    comment = {
      "The options in this section are only relevant if you're using voice control"
    },
    keys = {
      {
        name = "takeoff_FMA_readout",
        default = UserOptions.ENABLED,
        type = "bool",
        comment = "If enabled, the copilot will wait for you to confirm the FMA mode before their 'thrust set' takeoff callout. Example: 'MAN FLEX 68 SRS runway autothrust blue'"
      }
    }
  },
  {
    title = "Checklists",
    keys = {
      {
        name = "enable",
        default = UserOptions.TRUE,
        type = "bool"
      },
      {
        name = "display_info",
        default = UserOptions.FALSE,
        type = "bool"
      },
      {
        name = "display_fail",
        default = UserOptions.TRUE,
        type = "bool"
      },
      {
        name = "menu_keybind",
        default = nil,
        type = "string",
      }
    }
  },
  {
    title = "Callouts",
    keys = {
      {
        name = "enable", 
        default = UserOptions.TRUE, 
        type = "bool"
      },
      {
        name = "sound_set", 
        comment = "Name of a folder in copilot/sounds/callouts",
        default = "Peter", 
        type = "string"
      },
      {
        name = "volume",
        default = 100, 
        type = "int",
        comment = "This sets the maximum volume from 0-100. You can also adjust the volume with the INT volume knob in the cockpit",
      },
      {
        name = "ACP_volume_control",
        type = "bool",
        default = UserOptions.TRUE,
        hidden = true
      },
      {
        name = "device", 
        default = nil, 
        comment = "Leave blank for default device. The list of devices is at the top of the log file.", 
        type = "string"
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
        name = "parking",
        default = UserOptions.ENABLED,
        type = "bool"
      },
      {
        name = "securing_the_aircraft",
        default = UserOptions.ENABLED,
        type = "bool"
      },
      {
        name = "lineup_trigger",
        default = copilot.LINEUP_TRIGGER_SEAT_BELTS_SWITCH,
        comment = "explained in the manual",
        type = "enum",
        values = {copilot.LINEUP_TRIGGER_VOICE, copilot.LINEUP_TRIGGER_SEAT_BELTS_SWITCH}
      },
      {
        name = "after_landing_trigger", 
        default = copilot.AFTER_LANDING_TRIGGER_DISARM_SPOILERS, 
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
        name = "debug",
        default = UserOptions.DISABLED,
        hidden = true, 
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