local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local Button = require "FSL2Lua.FSL2Lua.Button"
local Guard = require "FSL2Lua.FSL2Lua.Guard"
local Switch = require "FSL2Lua.FSL2Lua.Switch"
local PushPullSwitch = require "FSL2Lua.FSL2Lua.PushPullSwitch"
local EngineMasterSwitch = require "FSL2Lua.FSL2Lua.EngineMasterSwitch"
local RotaryKnob = require "FSL2Lua.FSL2Lua.RotaryKnob"
local ToggleButton = require "FSL2Lua.FSL2Lua.ToggleButton"
local serpent = require "FSL2Lua.libs.serpent"
local util = require "FSL2Lua.FSL2Lua.util"
local file = require "FSL2Lua.FSL2Lua.file"
local Control = require "FSL2Lua.FSL2Lua.Control"

function Button:_checkMacro()

  local guard = self.guard

  if guard and not guard:isOpen() then
    guard:open()
    local timedOut = not checkWithTimeout(2000, function()
      return guard:isOpen()
    end)
    if timedOut then return false end
  end

  local LVarbefore = self:getLvarValue()
  self:macro "leftPress"
  if getmetatable(self) == ToggleButton then self:macro "leftRelease" end
  local timedOut = not self:_waitForLvarChange(2000, LVarbefore)
  if not timedOut then self:macro "leftRelease" end
  return not timedOut
end

function Button:_checkMacroManual()
  while true do
    self:macro "leftPress"
    repeatWithTimeout(500, coroutine.yield)
    self:macro "leftRelease"
    repeatWithTimeout(500, coroutine.yield)
  end
end

function Guard:_checkMacro()
  local LVarbefore = self:getLvarValue()
  if self:isOpen() then self:close()
  else self:open() end
  return self:_waitForLvarChange(2000, LVarbefore)
end

function Guard:_checkMacroManual()
  while true do
    self:macro "rightPress"
    repeatWithTimeout(500, coroutine.yield)
    self:macro "rightRelease"
    repeatWithTimeout(500, coroutine.yield)
  end
end

function Switch:_checkMacro()
  local LVarbefore = self:getLvarValue()
  if LVarbefore > 0 then self:decrease()
  else self:increase() end
  return self:_waitForLvarChange(5000, LVarbefore)
end

function Switch:_checkMacroManual()
  for _ = 1, 100 do
    self:increase()
  end
  while true do
    for _ = 1, 10 do self:decrease() end
    repeatWithTimeout(500, coroutine.yield)
    for _ = 1, 10 do self:increase() end
    repeatWithTimeout(500, coroutine.yield)
  end
end

function PushPullSwitch:_checkMacro()
  self:macro "leftRelease"
  self:macro "rightRelease"
  local LVarbefore = self:getLvarValue()
  self:macro "leftPress"
  return self:_waitForLvarChange(5000, LVarbefore)
end

function EngineMasterSwitch:_checkMacro()
  self:macro "leftRelease"
  self:macro "rightRelease"
  local LVarbefore = self:getLvarValue()
  self:macro "rightPress"
  return self:_waitForLvarChange(1000, LVarbefore)
end

function RotaryKnob:_checkMacroManual()
  for _ = 1, 100 do
    self:_rotateLeft()
  end
  while true do
    for _ = 1, 10 do self:_rotateLeft() end
    repeatWithTimeout(500, coroutine.yield)
    for _ = 1, 10 do self:_rotateRight() end
    repeatWithTimeout(500, coroutine.yield)
  end
end

function RotaryKnob:_checkMacro()
  if self.LVar:lower():find("comm") then
    local t
    for _, _t in ipairs{FSL, FSL.CPT, FSL.FO} do
      for _, control in pairs(_t) do
        if control == self then t = _t end
      end
    end
    for _, control in pairs(t) do
      if util.isType(control, Control) then
        local LVar = control.LVar:lower()
        local switch = LVar:find("switch") and LVar:find(self.LVar:lower():gsub("(.+)_.+","%1"))
        if switch and control.isDown and control:isDown() then
          control()
          local timedOut = not checkWithTimeout(2000, function()
            return not control:isDown()
          end)
          if timedOut then return false end
          break
        end
      end
    end
  end
  local LVarbefore = self:getLvarValue()
  if LVarbefore > 0 then self:_rotateLeft()
  else self:_rotateRight() end
  return self:_waitForLvarChange(1000, LVarbefore)
end

local manual = {}
local manualCheckCoroutine
local invalid = {}
local invalidManual = {}
local checkFile = {version = _FSL2LUA_VERSION}

local acType = FSL.acType

local checkFilePath = util.FSL2LuaDir .. "\\checked_macros.lua"

if file.exists(checkFilePath) then
  checkFile = dofile(checkFilePath)
  -- if checkFile.version ~= _FSL2LUA_VERSION then
  --   checkFile = {}
  -- end
end

local function collectkMissingMacros()
  local missing = {}
  for _, v in pairs(require "FSL2Lua.FSL2Lua.FSL") do
    if not v.ignore and not v.FSControl and not v[acType].rectangle and v[acType].available ~= false  then
      table.insert(missing, v)
    end
  end
  return missing
end

local function printSummary()
  local function comp(a, b) return a.name > b.name end
  table.sort(invalid, comp)
  table.sort(invalidManual, comp)
  print "Finished checking macros!"

  local missing = collectkMissingMacros()
  
  if #invalid > 0 or #invalidManual > 0 then
    if #invalid > 0 then
      print "------------------------------------------"
      print "Invalid non-manual controls:"
      for _, v in ipairs(invalid) do
        print(v.name)
      end
    end
    if #invalidManual > 0 then
      print "------------------------------------------"
      print "Invalid manual controls:"
      for _, v in ipairs(invalidManual) do
        print(v.name)
      end
    end
  end
  if #invalid == 0 and #invalidManual == 0 then
    print "------------------------------------------"
    print "All recorded macros are valid!"
  end
  if #missing > 0 then
    print "------------------------------------------"
    print "The macros for the following controls are missing:"
    for _, v in ipairs(missing) do print(v.LVar) end
  else 
    print "------------------------------------------"
    print "No missing macros!"
  end
  file.write(checkFilePath, "return " .. serpent.block(checkFile, {comment = false, sparse = false}),"w")
end

local function confirmControlIsValid(control)
  checkFile[control.LVar] = checkFile[control.LVar] or {}
  checkFile[control.LVar][acType] = "0x" .. string.format("%x", control.rectangle)
end

local function manualCheck()

  local timerStart
  local Apressed = false
  local Dpressed = false

  if not manualCheckCoroutine then
    Bind {
      key = "A",
      onPress = function()
        if Dpressed then return end
        Apressed = true
        timerStart = ipc.elapsedtime()
      end,
      onRelease = function() Apressed = false end
    }
    Bind {
      key = "D",
      onPress = function()
        if Apressed then return end
        Dpressed = true
        timerStart = ipc.elapsedtime()
      end,
      onRelease = function() Dpressed = false end
    }
  end

  manualCheckCoroutine = manualCheckCoroutine or coroutine.create(function()
    print("Starting manual check for " .. #manual .. " controls.")
    print "Hold 'A' for success or 'D' for failure."
    for _, control in ipairs(manual) do
      print(string.format("Checking control %s, rectangle = 0x%x", control.name, control.rectangle))
      local check = coroutine.wrap(function() control:_checkMacroManual() end)
      while true do 
        check()
        coroutine.yield()
        if (Apressed or Dpressed) and timerStart and ipc.elapsedtime() - timerStart > 1000 then
          if Apressed then
            print "Success!"
            confirmControlIsValid(control)
          else 
            print "Failure :("
            table.insert(invalidManual, control)
           end
          timerStart = nil
          break
        end
      end
    end
  end)
  if coroutine.status(manualCheckCoroutine) ~= "dead" then
    local ok, err = coroutine.resume(manualCheckCoroutine)
    if not ok then error(err) end
  else
    printSummary()
    event.cancel "ManualMacroCheck"
  end
end

local function CheckMacros()

  FSL.ignoreFaultyLvars()

  invalid = {}
  invalidManual = {}
  local checked = {}
  local notManual = {}

  local function checkControl(control)

    if util.isType(control, Control) and control._checkMacro and not control.FSControl then
      if checkFile[control.LVar] then
        if tonumber(checkFile[control.LVar][acType]) == control.rectangle then
          return
        end
      end

      if control.rectangle then
        if not control:_checkMacro() then
          if control[acType].manual and control._checkMacroManual then
            table.insert(manual, control)
          else
            print("The macro of control " .. control.name .. " appears to be invalid")
            table.insert(invalid, control)
          end
        else
          confirmControlIsValid(control)
          if control[acType].manual then
            table.insert(notManual, control)
          end
        end
      end
    end
  end

  local function checkMacros(table)
    for _, control in pairs(table) do
      if type(control) == "table" and control.LVar and control.LVar:lower():find("guard") then
        checkControl(control)
        checked[control] = true
      end
    end

    for _, control in pairs(table) do
      if not checked[control] then checkControl(control) end
    end
  end
  print"\n"
  print "-----------------------------------------------------------"
  print "--- Checking macros! --------------------------------------"
  print ("--- FSL2Lua version: " .. _FSL2LUA_VERSION .. " --------------------------------")
  print ("--- A/C type: " .. acType .. " ----------------------------------------")
  print "--- Delete FSL2Lua\\checked_macros.lua to reset the check --"
  print "-----------------------------------------------------------"
  print"\n"
  for _, button in ipairs {FSL.OVHD_FIRE_ENG1_PUSH_Button, FSL.OVHD_FIRE_ENG2_PUSH_Button, FSL.OVHD_FIRE_APU_PUSH_Button} do
    if not button:isDown() then
      checkControl(button)
    end
  end

  checkMacros(FSL)
  checkMacros(FSL.CPT)
  checkMacros(FSL.FO)

  if #notManual > 0 then
    print("The following controls are no longer manual for this type (" .. acType .. "):\n")
    for _, control in ipairs(notManual) do
      print(control.name)
    end
  end

  if #manual == 0 then
    printSummary()
  else
    ManualMacroCheck = manualCheck
    event.timer(1, "ManualMacroCheck")
  end

end

return CheckMacros