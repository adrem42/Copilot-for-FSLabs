
local content = [[

title = '%s'

project = '%s'

merge = true

file = {
  'Modules/FSL2lua/FSL2Lua/util.lua',
  'Modules/FSL2lua/FSL2Lua/Bind.lua',
  'Modules/FSL2lua/FSL2Lua/FSL2Lua.lua',

  'Modules/FSL2lua/FSL2Lua/Control.lua',

  'Modules/FSL2lua/FSL2Lua/Button.lua',
  'Modules/FSL2lua/FSL2Lua/ToggleButton.lua',

  'Modules/FSL2lua/FSL2Lua/Guard.lua',

  'Modules/FSL2lua/FSL2Lua/Switch.lua',
  'Modules/FSL2lua/FSL2Lua/FcuSwitch.lua',

  'Modules/FSL2lua/FSL2Lua/RotaryKnob.lua',

  'Modules/FSL2lua/FSL2Lua/MCDU.lua',


  'Modules/FSLabs Copilot.lua',
  'Modules/FSLabs Copilot/copilot/util.lua',
  'Modules/FSLabs Copilot/copilot/Event.lua',
  'Joystick/Joystick.h',
}

format = 'markdown'

readme = {
  'topics',
}

examples={'examples'}

backtick_references = true

kind_names={topic='Manual',module='Libraries'}

use_markdown_titles = true

no_space_before_args = true

convert_opt = false

pretty='lxsh'

]]

local file = require "Modules.FSL2Lua.FSL2Lua.file"

local versionInfo = file.read "Copilot\\versionInfo.h"

local versionString = versionInfo:match "COPILOT_VERSION [\"'](.+)[\"']"

if not versionString:match "%d%.%d%.%d" then
  error "Invalid version string"
end

versionString = string.format("Copilot for FSLabs %s", versionString)

file.write("config.ld", string.format(content , versionString, versionString), "w")