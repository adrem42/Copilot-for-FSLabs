if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

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

--- Count of cells in a line
---@int LENGTH_LINE 
MCDU.LENGTH_LINE = 24
--- Total line count
---@int NUM_LINES 
MCDU.NUM_LINES = 14
---Total cell count
---@int LENGTH 
MCDU.LENGTH = MCDU.LENGTH_LINE * MCDU.NUM_LINES

function MCDU:new(side, port)
  self.__index = self
  return setmetatable ({
    request = MCDUsession and MCDUsession:new(side, 0, port or 8080),
    sideStr = side == 1 and "CPT" or side == 2 and "FO"
  }, self)
end

function MCDU:_onHttpError()
  if not copilot.isSimRuning() then
    ipc.exit()
  end
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
      if response ~= "" then break end
      self:_onHttpError() 
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
    if display then break end
    self:_onHttpError() 
  end
  if startpos or endpos then
    return string.sub(display, startpos or 1, endpos or #display)
  end
  return display
end

--- Returns the start index and the end index of a line
--- @int lineNum
--- @treturn int Start index
--- @treturn int End index
function MCDU:getLineIdx(lineNum)
  local endIdx = self.LENGTH_LINE * lineNum
  local startIdx = endIdx - self.LENGTH_LINE + 1
  return startIdx, endIdx
end

--- Returns a line of the display
--- @int lineNum 
--- @string[opt] disp If you already have a display string, you can pass it here.
--- @int[opt=1] startPos
--- @int[opt=MCDU.LENGTH_LINE] endPos
--- @treturn string
function MCDU:getLine(lineNum, disp, startPos, endPos)
  disp = disp or self:getString()
  startPos = startPos or 1
  endPos = endPos or self.LENGTH_LINE
  local lineEndIdx = lineNum * self.LENGTH_LINE
  return disp:sub(lineEndIdx - self.LENGTH_LINE + startPos, lineEndIdx - (self.LENGTH_LINE - endPos))
end

--- Returns the last display line
-- @string[opt] disp If you already have a display string, you can pass it here.
--- @treturn string
function MCDU:getScratchpad(disp)
  return self:getLine(self.NUM_LINES, disp)
end

--- Types str on the keyboard.
---@string str
--- @usage FSL.CPT.MCDU:type "hello"
function MCDU:type(str)
  str = tostring(str)
  local _FSL = FSL[self.sideStr]
  local chars = {
    [" "] = "SPACE",
    ["."] = "DOT",
    ["/"] = "SLASH",
    ["-"] = "PLUSMINUS"
  }
  for i = 1, #str do
    local char = str:sub(i, i):upper()
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

---<span>
---
--- Prints information about each display cell in the following order:
---
--- * Display index
---
--- * Position in the line
---
--- * The character
---
--- * The code of the character
---
--- * Color
---
--- * Whether it's bold
---@int[opt=1] startLine
---@int[opt=MCDU.NUM_LINES] endLine   
function MCDU:printCells(startLine, endLine)
  startLine = startLine or 1
  endLine = endLine or self.NUM_LINES
  local arr = self:getArray()
  print()
  print("#### START OF " .. self.sideStr .. " MCDU INFO ####")
  print()
  for pos = self:getLineIdx(startLine), select(2, self:getLineIdx(endLine)) do
    local cell = arr[pos]
    if (pos - 1) % self.LENGTH_LINE == 0 then
      print "--------------------------------"
      print("Line " .. ((pos - 1) / self.LENGTH_LINE) + 1)
      print "---------------------------------"
    end
    print(string.format(
      "%-5s %-4s %-3s %-3s %-8s %s",
      pos, ((pos - 1) % self.LENGTH_LINE + 1),
      cell.char or "", cell.char and string.byte(cell.char) or "", 
      cell.color or "", 
      cell.isBold and "bold" or cell.isBold == false and "not bold" or ""
    ))
  end
  print()
  print("#### END OF " .. self.sideStr .. " MCDU INFO ####")
  print()
end

return MCDU