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
    if not checkWithTimeout(2000, guard.isOpen, guard) then return false end
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
          if not checkWithTimeout(2000, control.isDown, control) then return false end
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
local invalid = {}
local invalidManual = {}

local function numManual()
  local n = 0
  for _ in pairs(manual) do
    n = n + 1
  end
  return n
end

local checkFilePath = util.FSL2LuaDir .. "\\checked_macros.lua"

local checkFile = {}

local function printSummary()
  local function comp(a, b) return a.name > b.name end
  table.sort(invalid, comp)
  table.sort(invalidManual, comp)
  print "Finished checking controls!"

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
    print "All controls are valid!"
  end
  file.write(checkFilePath, "return " .. serpent.block(checkFile, {comment = false, sparse = false}),"w")
end

local function confirmControlIsValid(control)
  checkFile[control.LVar] = true
end

local function manualCheck()

  local titleFmt = "Manual control check - %d of %d"
  local i = 1
  for control in pairs(manual) do

    local title = titleFmt:format(i, numManual())
    local prompt = control.name
    local checkCoro = copilot.addCoroutine(function()
      control:_checkMacroManual()
    end)

    while true do
      local status, res = Event.waitForEvent(Event.fromTextMenu(title, prompt, {"Control is working", "Control is not working"}))
      if status == TextMenuResult.OK then
        if res == 1 then
          confirmControlIsValid(control)
        else
          table.insert(invalidManual, control)
        end
        break
      end
    end

    i = i + 1

    copilot.removeCallback(checkCoro)
  end

end

local function CheckMacros()

  manual = {}
  invalid = {}
  invalidManual = {}

  package.loaded["FSL2Lua.FLS2Lua.FSL2Lua"] = nil
  package.loaded["FSL2Lua.FSL2Lua.FSL"] = nil
  _G.FSL = require "FSL2Lua.FSL2Lua.FSL2Lua"
  _G.FSL:disableSequences()

  FSL = _G.FSL

  if file.exists(checkFilePath) then 
    checkFile = dofile(checkFilePath) 
  end

  FSL.ignoreFaultyLvars()

  invalid = {}
  invalidManual = {}
  local checked = {}
  local notManual = {}

  local function checkControl(control)

    if util.isType(control, Control) and control._checkMacro and not control.FSControl then
      if checkFile[control.LVar] == true then
        return
      end

      if control.name then
        if not control:_checkMacro() then
          if control.manual and control._checkMacroManual then
            manual[control] = true
          else
            print("The control " .. control.name .. " appears to not be working")
            table.insert(invalid, control)
          end
        else
          confirmControlIsValid(control)
          if control.manual then
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
      if not checked[control] and not manual[control] then checkControl(control) end
    end
  end
  print"\n"
  print "-----------------------------------------------------------"
  print "--- Checking macros! --------------------------------------"
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
    print("The following controls are no longer manual:\n")
    for _, control in ipairs(notManual) do
      print(control.name)
    end
  end

  if numManual() > 0 then
    if copilot.getCallbackStatus(coroutine.running()) then
      manualCheck()
    else
      copilot.addCoroutine(manualCheck)
    end
  end

  printSummary()

end

return CheckMacros