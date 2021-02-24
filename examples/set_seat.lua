-- @{standalonescripts.md|How do I launch this script?}

local FSL = require "FSL2Lua"

FSL:setPilot "FO"

local function tryOpenPage(key, pattern, init, plain)
  local function success() 
    return FSL.MCDU:getString():find(pattern, init, plain)
  end
  for _ = 1, 5 do
    key()
    if checkWithTimeout(1000, success) then return true end
  end
  return false
end

local function goToPage(steps)
  for i, v in ipairs(steps) do
    if not tryOpenPage(unpack(v)) then return false, i end
  end
  return true
end

local function readSelection()
  return FSL.MCDU:getString():sub(97, 97) == "[" and "CPT" or "FO" 
end

local function waitForDisplay()
  local init = FSL.MCDU:getString()
  repeat until FSL.MCDU:getString() ~= init
end

local function setSeat(getSelection)
  local ok, errIdx = goToPage {
    {FSL.PED_MCDU_KEY_MENU, "MCDU MENU"},
    {FSL.PED_MCDU_LSK_R5, "SYSTEMS 1"},
    {FSL.PED_MCDU_KEY_RIGHT, "SYSTEMS 2"},
    {FSL.PED_MCDU_KEY_RIGHT, "SEAT SELECTION"},
  }
  if not ok then
    return print("Attempt to open page #" .. errIdx .. " has timed out :(")
  end
  local newSelection = type(getSelection) == "string"
    and getSelection or getSelection(readSelection())
  local keyPress = 
    newSelection == "CPT" and FSL.PED_MCDU_LSK_L2 or FSL.PED_MCDU_LSK_R2
  local function changeSelection()
    keyPress() 
    return readSelection() == newSelection
  end
  if not checkWithTimeout(5000, changeSelection) then
    print "Attemp to set the seat selection has timed out :("
  end
end

local function toggleSeat()
  setSeat(function(currSelection)
    return currSelection == "CPT" and "FO" or "CPT"
  end)
end

Bind {key = "1", onPress = {setSeat, "CPT", FSL.PED_MCDU_KEY_FPLN, waitForDisplay}}
Bind {key = "2", onPress = {setSeat, "FO", FSL.PED_MCDU_KEY_FPLN, waitForDisplay}}
Bind {key = "3", onPress = {toggleSeat, FSL.PED_MCDU_KEY_PERF, waitForDisplay}}