
local content = [[

title = '%s'

project = '%s'

merge = true

file = {
  'FSUIPC folder/FSL2lua/FSL2Lua/util.lua',
  'FSUIPC folder/FSL2lua/FSL2Lua/Bind.lua',
  'FSUIPC folder/FSL2lua/FSL2Lua/FSL2Lua.lua',

  'FSUIPC folder/FSL2lua/FSL2Lua/Control.lua',

  'FSUIPC folder/FSL2lua/FSL2Lua/Button.lua',
  'FSUIPC folder/FSL2lua/FSL2Lua/ToggleButton.lua',

  'FSUIPC folder/FSL2lua/FSL2Lua/Guard.lua',

  'FSUIPC folder/FSL2lua/FSL2Lua/Switch.lua',
  'FSUIPC folder/FSL2lua/FSL2Lua/PushPullSwitch.lua',

  'FSUIPC folder/FSL2lua/FSL2Lua/RotaryKnob.lua',

  'FSUIPC folder/FSL2lua/FSL2Lua/MCDU.lua',


  'FSUIPC folder/FSLabs Copilot.lua',
  'FSUIPC folder/FSLabs Copilot/copilot/util.lua',
  'FSUIPC folder/FSLabs Copilot/copilot/Event.lua',
  'Joystick/Joystick.h',
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

convert_opt = false

pretty='lxsh'

]]

local file = require "FSUIPC folder.FSL2Lua.FSL2Lua.file"

local versionInfo = file.read "Copilot\\versionInfo.h"

local versionString = versionInfo:match "COPILOT_VERSION [\"'](.+)[\"']"

if not versionString:match "%d%.%d%.%d" then
  error "Invalid version string"
end

versionString = string.format("Copilot for FSLabs %s", versionString)

file.write("config.ld", string.format(content , versionString, versionString), "w")