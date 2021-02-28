
copilot.AFTER_LANDING_TRIGGER_VOICE = 1
copilot.AFTER_LANDING_TRIGGER_DISARM_SPOILERS = 2
copilot.TAKEOFF_PACKS_TURN_OFF = 0
copilot.TAKEOFF_PACKS_LEAVE_ALONE = 1

local UserOptions = {TRUE = 1, FALSE = 0, ENABLED = 1, DISABLED = 0}
copilot.UserOptions = UserOptions

return {
  {
    "General",
    {
      {
        "http_port", 8080,
        "The port of the web MCDU - leave it at default unless you changed it in the FSLabs settings", 
        type = "number"
      },
      {"log_level", 2, type = "int"},
      {
        "PM_seat", "right", 
        "Where the Pilot Monitoring sits in the cockpit - left or right", 
        type = "enum", values = {"left", "right"}, required = true
      },
      {"debugger", hidden = true, type = "bool"},
      {"debugger_bind", hidden = true, type = "string"},
      {"button_sleep_mult", hidden = true, type = "number"}
    }
  },
  {
    "Voice_control",
    {
      {"enable", UserOptions.TRUE, type = "bool"}
    }
  },
  {
    "Callouts",
    {
      {"sound_set", "Hannes", type = "string"},
      {"enable", UserOptions.TRUE, type = "bool"},
      {
        "volume", 60, type = "int",
        "This sets the maximum volume from 0-100. You can also adjust the volume with the INT volume knob in the cockpit",
      },
      {"device_id", -1, "-1 is the default device", type = "int"},
      {"PM_announces_flightcontrol_check", 1, type = "bool"},
      {"PM_announces_brake_check", 1, type = "bool"}
    }
  },
  {
    "Actions",
    {
      {"enable", UserOptions.ENABLED, type = "bool"},
      {
        "PM_clears_scratchpad", UserOptions.TRUE,
        "If enabled, PM will clear his scratchpad during the preflight FMGC check.",
        type = "bool"
      },
      {"preflight", UserOptions.ENABLED, type = "bool"},
      {"after_start", UserOptions.ENABLED, type = "bool"},
      {"during_taxi", UserOptions.ENABLED, type = "bool"},
      {"lineup", UserOptions.ENABLED, type = "bool"},
      {"takeoff_sequence", UserOptions.ENABLED, type = "bool"},
      {"after_takeoff", UserOptions.ENABLED, type = "bool"},
      {"ten_thousand_dep", UserOptions.ENABLED, type = "bool"},
      {"ten_thousand_arr", UserOptions.ENABLED, type = "bool"},
      {"after_landing", UserOptions.ENABLED, type = "bool"},
      {
        "after_landing_trigger", copilot.AFTER_LANDING_TRIGGER_VOICE, "explained in the manual", type = "enum", 
        values = {copilot.AFTER_LANDING_TRIGGER_VOICE, copilot.AFTER_LANDING_TRIGGER_DISARM_SPOILERS}
      },
      {"FDs_off_after_landing", UserOptions.TRUE, "explained in the manual", type = "bool"},
      {
        "packs_on_takeoff", copilot.TAKEOFF_PACKS_TURN_OFF,
        "If you make an ATSU performance request, whatever you enter there will override this option",
        type = "enum", values = {copilot.TAKEOFF_PACKS_TURN_OFF, copilot.TAKEOFF_PACKS_LEAVE_ALONE}
      },
      {"pack2_off_after_landing", 0, type = "bool"}
    }
  },
  {
    "Failures",
    {
      {"enable", UserOptions.DISABLED, type = "bool"},
      {"global_rate", 1 / 10000, type = "number"},
      {"per_airframe", UserOptions.TRUE, "track failures separately for each airframe - 1 or 0", type = "bool"},
    },
    {
      "If enable is set to 1, the script will set up random failures in the MCDU when the flight is loaded.",
      "By default, the rate of each failure is set to 1 / 10000 hours.",
      "You can change the global rate and the rate for each individual failure below"
    }
  }
}