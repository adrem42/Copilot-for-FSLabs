local util = require "FSL2Lua.FSL2Lua.util"

Checklist = {}

Checklist.CHECKLIST_RESET = {}
Checklist.CHECKLIST_CONTINUE = {}
Checklist.ITEM_RESET = {}
Checklist.DISABLE_DEFAULT = {}

Checklist.voiceCommands = {}

local function addVoiceCommand(...)
  local vc = VoiceCommand:new(...)
  Checklist.voiceCommands[vc] = true
  return vc
end

Checklist.sayAgainVoiceCommand  = addVoiceCommand {phrase = "say again"}
Checklist.standbyVoiceCommand   = addVoiceCommand {phrase = "standby checklist"}
Checklist.resumeVoiceCommand    = addVoiceCommand {phrase = "resume checklist"}
Checklist.restartVoiceCommand   = addVoiceCommand {phrase = "restart checklist"}

function Checklist:new(name, trigger)
  self.__index = self
  local checklist = setmetatable({
    items = {},
    name = name,
    trigger = trigger
  }, self)
  trigger:addAction(function()
    copilot.addCoroutine(function()
      checklist:execute()
    end)
  end)
  return checklist
end

function Checklist:_playCallout(fileName)
  copilot.playCallout("checklists." .. self.name .. "." .. fileName)
end

function Checklist:_awaitResponse(item)
  local events = {
    self.standbyVoiceCommand,
    self.sayAgainVoiceCommand,
    self.restartVoiceCommand
  }
  for vc in pairs(item.response) do
    events[#events+1] = vc:activate()
  end
  self.standbyVoiceCommand:activate()
  self.sayAgainVoiceCommand:activate()
  self.restartVoiceCommand:activate()
  local vc, recoResult = Event.waitForEvents(events)
  if vc == self.sayAgainVoiceCommand then
    return self:_executeItem(item)
  elseif vc == self.standbyVoiceCommand then
    return self:_awaitResume(item)
  elseif vc == self.restartVoiceCommand then
    return self.CHECKLIST_RESET
  else
    for _vc in pairs(item.response) do
      _vc:deactivate()
    end
    if not item.onResponse then
      return self.CHECKLIST_CONTINUE
    end
    local res, default = item.onResponse(
      item.response[vc], vc, recoResult
    )
    if type(res) == "boolean" then
      res = res and self.CHECKLIST_CONTINUE or self.ITEM_RESET
    end
    if res == self.ITEM_RESET then
      if default ~= self.DISABLE_DEFAULT then
        --copilot.sleep(500, 1500)
        copilot.playCallout("checklists.doubleCheck")
      end
      return self:_awaitResponse(item)
    end
    return res, default
  end
end

function Checklist:_awaitResume(item)
  self.standbyVoiceCommand:ignore()
  self.resumeVoiceCommand:activate()
  for vc in pairs(item.response) do
    vc:ignore()
  end
  --copilot.sleep(1000, 1500)
  local vc = Event.waitForEvents {self.resumeVoiceCommand, self.restartVoiceCommand}
  if vc == self.restartVoiceCommand then
    return self.CHECKLIST_RESET
  end
  self:_playCallout(item.name)
  return self:_awaitResponse(item)
end

function Checklist:_executeItem(item)
  --copilot.sleep(1000, 1500)
  self:_playCallout(item.name)
  return self:_awaitResponse(item)
end

function Checklist:execute()

  if not copilot.getCallbackStatus(coroutine.running()) then
    error("Checklist.execute must be called from a coroutine added via a copilot API", 2)
  end
  self.executing = true
  copilot.sleep(1000, 1500)
  self:_playCallout "announce"

  local vcStates = {}

  for _, voiceCommand in pairs(Event.voiceCommands) do
    if not self.voiceCommands[voiceCommand] then
      local state = voiceCommand:getState()
      if state ~= RuleState.Inactive and state ~= RuleState.Disabled then
        vcStates[voiceCommand] = state
        voiceCommand:deactivate()
      end
    end
  end

  for _, item in ipairs(self.items) do
    local res, default = self:_executeItem(item)
    if res == self.CHECKLIST_RESET then
      return self:execute()
    elseif default ~= self.DISABLE_DEFAULT then
      copilot.playCallout("checklists.checked_" .. math.random(1, 5))
    end
  end

  for voiceCommand, state in pairs(vcStates) do
    if state == RuleState.Active then
      voiceCommand:activate()
    elseif state == RuleState.Ignore then
      voiceCommand:ignore()
    end
  end

  self:_playCallout "completed"

  self.executing = false

end

function Checklist:_insertItem(pos, newItem)
  if self.executing then
    error("Not allowed to add items while executing checklist", 3)
  end
  table.insert(self.items, pos, newItem)
  if util.isType(newItem.response, VoiceCommand) then
    newItem.response = {[""] = newItem.response}
  end
  local response = {}
  for name, vc in pairs(newItem.response) do
    self.voiceCommands[vc] = true
    response[vc] = name
  end
  newItem.response = response
end

function Checklist:appendItem(newItem)
  self:_insertItem(#self.items+1, newItem)
  return self
end

function Checklist:insertItem(itemBefore, newItem)
  for i, item in ipairs(self.items) do
    if item.name == itemBefore then
      self:_insertItem(i, newItem)
      break
    end
  end
  return self
end

function Checklist:removeItem(itemName)
  if self.executing then
    error("Not allowed to remove items while executing checklist", 2)
  end
  for i, item in ipairs(self.items) do
    if item.name == itemName then
      table.remove(self.items, i)
      for _, vc in ipairs(item.responseVc) do
        self.voiceCommands[vc] = nil
      end
      return
    end
  end
  return self
end
