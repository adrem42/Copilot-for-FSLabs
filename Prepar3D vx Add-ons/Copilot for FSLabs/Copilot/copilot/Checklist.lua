local util = require "FSL2Lua.FSL2Lua.util"

Checklist = {}
Checklist.CHECKLIST_RESET = {}
Checklist.CHECKLIST_CANCEL = {}
Checklist.CHECKLIST_SKIP = {}
Checklist.ITEM_SKIP = {}
Checklist.ITEM_CONTINUE = {}
Checklist.ITEM_RESET = {}

Checklist.voiceCommands = {}

local function addVoiceCommand(...)
  local vc = VoiceCommand:new(...)
  Checklist.voiceCommands[vc] = true
  return vc
end

Checklist.sayAgainVoiceCommand  = addVoiceCommand {phrase = "say again"}
Checklist.standbyVoiceCommand   = addVoiceCommand {phrase = "standby checklist"}
Checklist.resumeVoiceCommand    = addVoiceCommand {phrase = "resume checklist"}
Checklist.restartEvent          = addVoiceCommand {phrase = "restart checklist"}

Checklist.skipItemEvent         = Event:new {logMsg = "Skip checklist item"}
Checklist.skipChecklistEvent    = Event:new {logMsg = "Skip checklist"}
Checklist.cancelChecklistEvent  = Event:new {logMsg = "Cancel checklist"}

local function prettyName(checklistOrItem)
  return checklistOrItem.displayLabel or checklistOrItem.name
end

function Checklist:new(label, displayLabel, trigger)
  self.__index = self
  local checklist = setmetatable({
    items = {},
    label = label,
    displayLabel = displayLabel,
    trigger = trigger,
    doneEvent = Event:new {logMsg = "Checklist " .. label .. " finished"}
  }, self)
  trigger:addAction(function()
    copilot.addCoroutine(function()
      checklist:execute()
    end)
  end)
  return checklist
end

function Checklist:playCallout(fileName)
  if fileName:sub(1, 7) == "common." then
    copilot.playCallout("checklists.common" .. fileName)
  else
    copilot.playCallout("checklists." .. self.label .. "." .. fileName)
  end
end

function Checklist:_handleCommonEvents(event)
  if event == self.restartEvent then
    return {res = self.CHECKLIST_RESET}
  elseif event == self.skipItemEvent then
    return {res = self.CHECKLIST_CONTINUE, disableDefault = true}
  elseif event == self.cancelChecklistEvent then
    return {res = self.CHECKLIST_CANCEL}
  elseif event == self.skipChecklistEvent then
    return {res = self.CHECKLIST_SKIP}
  end
end

function Checklist.currChecklist()
  local checklist = Checklist._currChecklist
  if not checklist then return end
  return checklist, checklist:currItem()
end

function Checklist:currItem()
  return self._currItem
end

function Checklist:_handleResponse(item, responseVcName, responseVc, recoResult)

  if not item.onResponse then
    return {res = self.CHECKLIST_CONTINUE}
  end

  local failed = {}
  local didFail = false

  local function onFailed(reason)
    didFail = true
    if reason then
      failed[#failed+1] = reason
    end
  end

  local res = {}

  item.onResponse(responseVcName, responseVc, recoResult, onFailed, res)

  if not res.res then
    res.res = didFail and self.ITEM_RESET or self.CHECKLIST_CONTINUE
  end

  if #failed > 0 then
    local msg = string.format(
      "Checklist item %s - %s failed:\n - %s",
      prettyName(self), prettyName(item), table.concat(failed, "\n - ")
    )
    print(msg)
    if copilot.UserOptions.checklists.display_fail == copilot.UserOptions.TRUE then
      copilot.displayText(msg, 10, "red")
    end
  end

  if res.res == self.ITEM_RESET then
    if not res.disableDefault then
      copilot.playCallout("checklists.doubleCheck")
    end
    return self:_awaitResponse(item)
  end

  return res
end

function Checklist:onVcStateChange(vc, state)
  if not self.voiceCommandsSuspended then return false end
  self.vcStates[vc] = state
  return true
end

function Checklist:_awaitResponse(item)

  local events = {
    self.standbyVoiceCommand:activate(),
    self.sayAgainVoiceCommand:activate(),
    self.restartEvent:activate(),
    self.skipItemEvent,
    self.skipChecklistEvent,
    self.cancelChecklistEvent
  }

  local vcLabels = {}
  local numNonResponseEvents = #events

  for label, vc in pairs(item.response) do
    events[#events+1] = vc:activate()
    vcLabels[vc] = label
  end

  local event, recoResult, eventIdx = Event.waitForEvents(events)

  if event == self.sayAgainVoiceCommand then
    return self:_executeItem(item)
  elseif event == self.standbyVoiceCommand then
    return self:_awaitResume(item)
  elseif eventIdx > numNonResponseEvents then
    for _, vc in pairs(item.response) do
      vc:deactivate()
    end
    return self:_handleResponse(item, vcLabels[event], event, recoResult())
  else
    return self:_handleCommonEvents(event)
  end
end

function Checklist:_awaitResume(item)
  self.standbyVoiceCommand:ignore()
  for _, vc in pairs(item.response) do
    vc:ignore()
  end
  self:_resumeVoiceCommands()
  local event = Event.waitForEvents {
    self.resumeVoiceCommand:activate(), 
    self.restartEvent, 
    self.skipItemEvent,
    self.skipChecklistEvent,
    self.cancelChecklistEvent
  }
  if event == self.resumeVoiceCommand then
    self:_suspendVoiceCommands()
    self:playCallout(item.label)
    return self:_awaitResponse(item)
  end
  return self:_handleCommonEvents(event)
end

function Checklist:_executeItem(item)
  self:playCallout(item.label)
  if item.beforeChallenge then
    item.beforeChallenge(item)
  end
  return self:_awaitResponse(item)
end

function Checklist:_suspendVoiceCommands()
  if self.voiceCommandsSuspended then return end
  self.vcStates = {}
  for _, voiceCommand in pairs(Event.voiceCommands) do
    if not self.voiceCommands[voiceCommand] then
      local state = voiceCommand:getState()
      if state ~= RuleState.Inactive and state ~= RuleState.Disabled then
        self.vcStates[voiceCommand] = state
        voiceCommand:deactivate()
      end
    end
  end
  self.voiceCommandsSuspended = true
end

function Checklist:_resumeVoiceCommands()
  if not self.voiceCommandsSuspended then return end
  self.voiceCommandsSuspended = false
  for voiceCommand, state in pairs(self.vcStates) do
    if state == RuleState.Active then
      voiceCommand:activate()
    elseif state == RuleState.Ignore then
      voiceCommand:ignore()
    elseif state == RuleState.Disabled then
      voiceCommand:disable()
    end
  end
end

function Checklist:execute()

  if Checklist._currChecklist then
    self.trigger:activate()
    return
  end

  Checklist._currChecklist = self

  if not copilot.getCallbackStatus(coroutine.running()) then
    error("Checklist.execute must be called from a coroutine added via a copilot API", 2)
  end
  self.executing = true
  copilot.sleep(1000, 1500)
  self:playCallout "announce"

  self:_suspendVoiceCommands()

  local completionStatus = "completed"

  for _, item in ipairs(self.items) do
    self._currItem = item
    local res = self:_executeItem(item)
    for _, vc in pairs(item.response) do
      vc:deactivate()
    end
    if res.res == self.CHECKLIST_RESET then
      print("Resetting checklist: " .. self.displayLabel)
      return self:execute()
    elseif res.res == self.CHECKLIST_CANCEL then
      print("Checklist canceled: " .. self.displayLabel)
      completionStatus = "canceled"
      self.trigger:activate()
      break
    elseif res.res == self.CHECKLIST_SKIP then
      print("Skipping checklist: " .. self.displayLabel)
      completionStatus = "skipped"
      break
    elseif not res.disableDefault and (res.acknowledge or item.acknowledge) then
      self:playCallout(res.acknowledge or item.acknowledge)
    end
  end
  self._currItem = nil

  if completionStatus == "completed" then
    self:playCallout "completed"
  end

  self.executing = false
  Checklist._currChecklist = nil

  self:_resumeVoiceCommands()

  self.doneEvent:trigger(completionStatus)

end

function Checklist:_insertItem(pos, item, replace)
  if self.executing then
    error("Not allowed to add items while executing checklist", 3)
  end
  if replace then
    self.items[pos] = item
  else
    table.insert(self.items, pos, item)
  end
  if util.isType(item.response, VoiceCommand) then
    item.response = {response = item.response}
  end
  for _, vc in pairs(item.response) do
    self.voiceCommands[vc] = true
  end
end

function Checklist:appendItem(item)
  self:_insertItem(#self.items+1, item)
  return self
end

function Checklist:findItem(label)
  for i, item in ipairs(self.items) do
    if item.label == label then
      return item, i
    end
  end
end

function Checklist:replaceItem(label, item)
  self:_insertItem(select(2, self:findItem(label)), item, true)
  return self
end

function Checklist:insertItem(label, item)
  self:_insertItem(select(2, self:findItem(label)), item)
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

local checklistMenu = {
  {
    text = "Restart checklist",
    action = function()
      Checklist.restartEvent:trigger()
    end
  },
  {
    text = "Skip current item",
    action = function()
      Checklist.skipItemEvent:trigger()
    end
  },
  {
    text = "Cancel checklist",
    action = function()
      Checklist.cancelChecklistEvent:trigger()
    end
  },
  {
    text = "Skip checklist",
    action = function()
      Checklist.skipChecklistEvent:trigger()
    end
  }
}

local menuItems = {}
for _, menuItem in ipairs(checklistMenu) do
  menuItems[#menuItems+1] = menuItem.text
end
menuItems[#menuItems+1] = "Cancel"

local textMenu = TextMenu.new()
textMenu:setTimeout(10)

local function showMenu()

  local checklist, item = Checklist.currChecklist()
  
  if not checklist then
    textMenu:setTitle"No checklist is being executed":setPrompt"":setItems{"OK"}:show()
    return
  end

  local prompt = prettyName(checklist) .. " - " .. prettyName(item)

  local function checkItemChanged()
    if select(2, Checklist.currChecklist()) == item then
      return false
    end
    textMenu:setTitle"The current checklist item has changed":setPrompt"":setItems{"OK"}:show()
    return true
  end

  textMenu:setTitle"Select action for the current checklist:":setPrompt(prompt):setItems(menuItems):show()

  local status, res, text = Event.waitForEvent(textMenu:getEvent())
  if status ~= TextMenuResult.OK or res == #menuItems or checkItemChanged() then 
    return 
  end

  textMenu:setTitle"Are you sure?":setPrompt(text .. ": " .. prompt):setItems{"Yes", "Cancel"}:show()
  status, res = Event.waitForEvent(textMenu:getEvent())
  if res == 1 and not checkItemChanged() then 
    checklistMenu[res].action() 
  end
end

if copilot.UserOptions.checklists.menu_keybind then
  Bind {
    key = copilot.UserOptions.checklists.menu_keybind,
    onPress = function()
      copilot.addCoroutine(showMenu)
    end
  }
end
