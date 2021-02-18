if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"

--- @type MCDU

local MCDU = {
  colors = {
    ["1"] = "cyan",
    ["2"] = "grey",
    ["4"] = "green",
    ["5"] = "magenta",
    ["6"] = "amber",
    ["7"] = "white",
  },
}

function MCDU:new(side)
  self.__index = self
  return setmetatable ({
    request = McduHttpRequest and McduHttpRequest:new(side, 8080),
    sideStr = side == 1 and "CPT" or side == 2 and "FO"
  }, self)
end

function MCDU:_onHttpError()
  util.handleError(string.format("%s MCDU HTTP request error %s, retrying...",
                            self.sideStr, self.request:lastError()), 3)
end

--- Returns the MCDU display as an array of display cells.
--- @treturn table Array of tables representing display cells.
--
--- Each cell table has three fields:
--
-- * char: The character displayed in the cell (nil if the cell is blank)
-- * color: The color of the character, one of these : 
--    * 'cyan' 
--    * 'grey' 
--    * 'green' 
--    * 'magenta' 
--    * 'amber' 
--    * 'white' 
-- * isBold: bool
function MCDU:getArray()
    local response
    while true do
      response = self.request:getRaw()
      if response ~= "" then break
      else self:_onHttpError() end
    end
    local display = {}
    for unitArray in response:gmatch("%[(.-)%]") do
      local unit = {}
      if unitArray:find(",") then
        local char, color, isBold = unitArray:match("(%d+),(%d),(%d)")
        unit.char = string.char(char)
        unit.color = self.colors[color] or tonumber(color)
        unit.isBold = tonumber(isBold) == 0
      end
      display[#display+1] = unit
    end
    return display
end

--- Returns the MCDU display as a string.
--- @treturn string
--- @number[opt] startpos
--- @number[opt] endpos
--- @usage 
--- if not FSL.MCDU:getString():find "MCDU MENU" then
---   FSL.PED_MCDU_KEY_MENU()
--- end
function MCDU:getString(startpos, endpos)
  local display
  while true do
    display = self.request:getString()
    if display then break
    else self:_onHttpError() end
  end
  if startpos or endpos then
    return string.sub(display, startpos, endpos)
  else
    return display
  end
end

--- Returns the scratchpad - the last line on the display.
--- @treturn string
function MCDU:getScratchpad()
  return self:getString(313)
end

--- Types str on the keyboard.
---@string str
--- @usage FSL.CPT.MCDU:type "hello"
function MCDU:type(str)
  str = tostring(str)
  local _FSL = FSL[self.sideStr]
  for i = 1, #str do
    local chars = {
      [" "] = "SPACE",
      ["."] = "DOT",
      ["/"] = "SLASH",
      ["-"] = "PLUSMINUS"
    }
    local char = str:sub(i,i):upper()
    char = chars[char] or char
    if char == "+" then
      _FSL.PED_MCDU_KEY_PLUSMINUS()
      _FSL.PED_MCDU_KEY_PLUSMINUS()
    else
      _FSL["PED_MCDU_KEY_" .. char]()
    end
  end
end

--- Returns false if the display is blank.
--- @treturn bool
function MCDU:isOn()
  return self:getString():find("%S") ~= nil
end

--- Prints information about each display cell: its index, character (including its numerical representation) and whether it's bold.
function MCDU:printCells()
  for pos,cell in ipairs(self:getArray()) do
    print(pos, 
          cell.char and string.format("%s (%s)", cell.char, string.byte(cell.char)) or "", 
          cell.color or "", 
          cell.isBold and "bold" or cell.isBold == false and "not bold" or "")
  end
end

return MCDU