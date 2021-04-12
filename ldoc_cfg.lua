
local content = [[

convert_opt = true

title = '%s'

project = '%s'

merge = true

file = {
  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/util.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/Bind.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/FSL2Lua.lua',

  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/Control.lua',

  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/Button.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/ToggleButton.lua',

  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/Guard.lua',

  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/Switch.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/PushPullSwitch.lua',

  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/RotaryKnob.lua',

  'Prepar3D vx Add-ons/Copilot for FSLabs/FSL2lua/FSL2Lua/MCDU.lua',

  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/Copilot.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/Copilot/IniUtils.lua',
  'Copilot/CallbackRunner.cpp',
  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/copilot/util.lua',

  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/copilot/Action.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/copilot/Event.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/copilot/ActionOrderSetter.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/copilot/SingleEvent.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/copilot/VoiceCommand.lua',
  'Prepar3D vx Add-ons/Copilot for FSLabs/Copilot/copilot/Checklist.lua',
  'Copilot/Joystick.h',
  'Copilot/CopilotScript.cpp'
}

format = 'markdown'

readme = {
  'topics',
}

style='!pale'

examples={'examples'}

backtick_references = true

kind_names={topic='Manual',module='Libraries'}

use_markdown_titles = true

no_space_before_args = true

pretty='lxsh'

]]

local file = require "Prepar3D vx Add-ons.Copilot for FSLabs.FSL2Lua.FSL2Lua.file"

local versionInfo = file.read "Copilot\\versionInfo.h"

local versionString = versionInfo:match "COPILOT_VERSION [\"'](.+)[\"']"

if not versionString:match "%d%.%d%.%d" then
  error "Invalid version string"
end

versionString = string.format("Copilot for FSLabs %s", versionString)

file.write("config.ld", string.format(content , versionString, versionString), "w")