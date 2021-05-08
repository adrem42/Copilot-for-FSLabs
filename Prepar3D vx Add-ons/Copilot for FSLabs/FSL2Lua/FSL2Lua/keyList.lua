require "FSL2Lua.FSL2Lua.extensions"

local keys = {

  Backspace   = 0x08, -- VK_BACK
  Clear       = 0x0C, -- VK_CLEAR
  Enter       = 0x0D, -- VK_RETURN
  Pause       = 0x13, -- VK_PAUSE
  CapsLock    = 0x14, -- VK_CAPITAL
  Esc         = 0x1B, -- VK_ESCAPE
  Space       = 0x20, -- VK_SPACE
  PageUp      = 0x21, -- VK_PRIOR
  PageDown    = 0x22, -- VK_NEXT
  End         = 0x23, -- VK_END
  Home        = 0x24, -- VK_HOME
  LeftArrow   = 0x25, -- VK_LEFT
  UpArrow     = 0x26, -- VK_UP 
  RightArrow  = 0x27, -- VK_RIGHT
  DownArrow   = 0x28, -- VK_DOWN
  Select      = 0x29, -- VK_SELECT
  Print       = 0x2A, -- VK_PRINT
  Execute     = 0x2B, -- VK_EXECUTE
  PrintScreen = 0x2C, -- VK_SNAPSHOT
  Insert      = 0x2D, -- VK_INSERT
  Ins         = 0x2D, -- VK_INSERT
  Delete      = 0x2E, -- VK_DELETE
  Del         = 0x2E, -- VK_DELETE
  Help        = 0x2F, -- VK_HELP
  -- Numpad0, Numpad1, ...
  Mult        = 0x6A, -- VK_MULTIPLY
  Add         = 0x6B, -- VK_ADD
  Sep         = 0x6C, -- VK_SEPARATOR
  Sub         = 0x6D, -- VK_SUBTRACT
  Dec         = 0x6E, -- VK_DECIMAL
  Div         = 0x6F, -- VK_DIVIDE
  -- F1, F2, ...
  NumLock     = 0x90, -- VK_NUMLOCK
  ScrollLock  = 0x91, -- VK_SCROLL

}

for i = 1, 22 do keys["F" .. i] = i +  111 end
for i = 0, 9  do keys["Numpad" .. i] = i + 96 end

local modifiers = {

  Tab       = 0x9,  -- VK_TAB
  LShift    = 0xA0, -- VK_LSHIFT
  RShift    = 0xA1, -- VK_RSHIFT
  LControl  = 0xA2, -- VK_LCONTROL
  LCtrl     = 0xA2, -- VK_LCONTROL
  RControl  = 0xA3, -- VK_RCONTROL
  RCtrl     = 0xA3, -- VK_RCONTROL
  LAlt      = 0xA4, -- VK_LMENU
  RAlt      = 0xA5, -- VK_RMENU
  LWin      = 0x5B, -- VK_LWIN
  RWin      = 0x5C, -- VK_RWIN
  Apps      = 0x5D, -- VK_APPS

  Shift     = 0x10, -- VK_SHIFT
  Control   = 0x11, -- VK_CONTROL
  Ctrl      = 0x11,
  Alt       = 0x12  -- VK_MENU

}

return { 
  keys = table.mapKeys(keys, string.upper), 
  modifiers = table.mapKeys(modifiers, string.upper)
}