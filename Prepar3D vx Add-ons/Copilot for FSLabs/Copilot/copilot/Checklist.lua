---------------------------
---
--- @classmod Checklist


local util = require "FSL2Lua.FSL2Lua.util"

Checklist = {}

Checklist.voiceCommands = {}

local function addVoiceCommand(...)
  local vc = VoiceCommand:new(...)
  Checklist.voiceCommands[vc] = true
  return vc
end

Checklist.checklistEvent = Event:new()

Checklist.sayAgainVoiceCommand  = addVoiceCommand "say again"
Checklist.standbyVoiceCommand   = addVoiceCommand "standby checklist"
Checklist.resumeVoiceCommand    = addVoiceCommand {"resume checklist", "continue checklist"}
Checklist.restartVoiceCommand   = addVoiceCommand {
  phrase = "restart checklist",
  action = function() Checklist.checklistEvent:trigger "checklist_reset" end
}

local function getDisplayLabel(checklistOrItem)
  return checklistOrItem.displayLabel or checklistOrItem.label
end

local function itemInfo(checklist, item, itemIdx)
  return ("%s - %s (%d/%d)"):format(
    getDisplayLabel(checklist), getDisplayLabel(item), 
    itemIdx or select(2, checklist:currItem()), #checklist.items
  )
end

local function resetCurrChecklist()
  Checklist._currItem = nil
  Checklist._currChecklist = nil
  Checklist._currItemIdx = nil
end

---Constructor
---@string label The name of the folder in *copilot\sounds\callouts* where the checklist-related callouts are located.
---@string displayLabel Name of the checklist that will be displayed in the message windows and logs
---@param trigger A VoiceCommand that's going to be the trigger for your checklist. It can be accessed through the *trigger* field.
---Use it to control the availability of the checklist by calling `myChecklist.trigger:activate()/deactivate()` (see *copilot\initChecklists.lua*)
function Checklist:new(label, displayLabel, trigger)
  self.__index = self
  local checklist
  checklist = setmetatable({
    items = {},
    label = label,
    displayLabel = displayLabel,
    trigger = trigger,
    _action = trigger:addAction(function() return checklist:execute() end, Action.COROUTINE)
  }, self)
  checklist._action:doneEvent():addAction(function(_, res)
    if res == copilot.THREAD_REMOVED then
      resetCurrChecklist()
      if self._doneEvent then self._doneEvent:trigger "error" end
    end
    self.sayAgainVoiceCommand:deactivate()
    self.standbyVoiceCommand:deactivate()
    self.resumeVoiceCommand:deactivate()
    self.restartVoiceCommand:deactivate()
  end)
  return checklist
end

function Checklist:_incVcCount(vc)
  self.voiceCommands[vc] = (self.voiceCommands[vc] or 0) + 1
end

function Checklist:_decVcCount(vc)
  self.voiceCommands[vc] = (self.voiceCommands[vc] or 0) - 1
  if self.voiceCommands[vc] <= 0 then
    self.voiceCommands[vc] = nil
  end
end

function Checklist:doneEvent()
  if not self._doneEvent then
    self._doneEvent = Event:new {logMsg = Event.NOLOGMSG}
    self._action:doneEvent():addAction(function(_, ...) self._doneEvent:trigger(...) end)
  end
  return self._doneEvent
end

function Checklist:_playCallout(fileName, delay)
  local prefix = "checklists."
  if fileName:sub(1, #prefix) == prefix then
    copilot.playCallout(fileName, delay)
  else
    copilot.playCallout(prefix .. self.label .. "." .. fileName, delay)
  end
end

function Checklist:_getCommonEvents()
  self.restartVoiceCommand:activate()
  return self.checklistEvent
end

--- Returns the checklist that is currently being executed
---@static
---@return The checklist itself or nil.
---@return The current item, if there is a checklist, or nil.
function Checklist.currChecklist()
  local checklist = Checklist._currChecklist
  if not checklist then return end
  return checklist, checklist:currItem()
end

---Returns the current item that is being executedm or nil.
function Checklist:currItem()
  return self._currItem, self._currItemIdx
end

local function makeCheckFunc()
  local failed = {}
  return failed, function (arg1, message)
    local val
    if not message then
      val = false
      message = arg1
    else
      val = arg1
    end
    if not val then
      failed[#failed+1] = message
    end
    return val and true or false
  end
end

function Checklist:_handleResponse(item, responseLabel, recoResult, phrases)

  if not item.onResponse then
    return {res = "checklist_continue"}
  end

  local failed, check = makeCheckFunc()

  local res = {didFail = function() return #failed > 0 end}

  if not item.onResponseCoroutine then
    item.onResponse(check, recoResult, responseLabel, res, item)
  else
    local co, onResponseThread = copilot.addCoroutine(function()
      item.onResponse(check, recoResult, responseLabel, res, item)
    end)
    self.restartVoiceCommand:deactivate()
    local e, payload = Event.waitForEvents {onResponseThread, self.checklistEvent}
    if e == self.checklistEvent then
      copilot.removeCallback(co)
      return self:_handleCommonEvents(payload()) 
    end
  end

  if not res.res then
    res.res = res.didFail() and "item_reset_after_fail" or "checklist_continue"
  end

  if #failed > 0 then
    local msg = string.format(
      "Checklist item %s failed; phrase: '%s'; confidence: %.4f\n\n%s",
      itemInfo(self, item),
      recoResult.phrase, recoResult.confidence, 
      table.concat(failed, "\n")
    )
    print(msg)
    if copilot.UserOptions.checklists.display_fail == copilot.UserOptions.TRUE then
      if copilot.UserOptions.checklists.display_info == copilot.UserOptions.TRUE then
        msg = msg .. "\n\nResponse variants:\n\n" .. table.concat(phrases, "\n")
      end
      self.didShowText = true
      copilot.displayText(msg, 40, "print_yellow")
    end
  end

  if res.res == "item_reset_after_fail" then
    if not res.disableDefault then
      self:_playCallout("checklists.doubleCheck")
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

function Checklist:_handleCommonEvents(payload)
  return {res = payload}
end

function Checklist:_awaitResponse(item)

  item.numRetries = item.numRetries + 1
  local commonEvents = self:_getCommonEvents()
  local events = {self.standbyVoiceCommand:activate(), self.sayAgainVoiceCommand:activate(), commonEvents}
  local responseLabels = {}
  local phrases = {}

  for label, vc in pairsByKeys(item.response) do
    events[#events+1] = vc:activate()
    responseLabels[vc] = label
    for _, phrase in ipairs(vc:getPhrases()) do
      phrases[#phrases+1] = tostring(phrase)
    end
  end

  if item.numRetries == 0 and copilot.UserOptions.checklists.display_info == copilot.UserOptions.TRUE then
    self.didShowText = true
    copilot.displayText(string.format(
      "Checklist item: %s\nResponse variants:\n\n%s",
      itemInfo(self, item), 
      table.concat(phrases, "\n")), 
      40
    )
  end

  local event, payload = Event.waitForEvents(events)

  if event == self.sayAgainVoiceCommand then
    self:_playCallout(item.label)
    return self:_awaitResponse(item)
  elseif event == self.standbyVoiceCommand then
    return self:_onStby(item)
  elseif event == commonEvents then
    return self:_handleCommonEvents(payload())
  else
    for _, vc in pairs(item.response) do
      vc:deactivate()
    end
    return self:_handleResponse(item, responseLabels[event], payload(), phrases)
  end
end

function Checklist:_onStby(item)
  self.standbyVoiceCommand:ignore()
  self:_playCallout "checklists.standingBy"
  for _, vc in pairs(item.response) do
    vc:ignore()
  end
  self:_resumeVoiceCommands()
  local event, payload = Event.waitForEvents {self.resumeVoiceCommand:activate(), self:_getCommonEvents()}
  if event == self.resumeVoiceCommand then
    self:_suspendVoiceCommands()
    self:_playCallout(item.label)
    return self:_awaitResponse(item)
  end
  return self:_handleCommonEvents(payload())
end

function Checklist:_executeItem(item)
  if self.didShowText and copilot.UserOptions.checklists.display_info == copilot.UserOptions.FALSE then
    self.didShowText = false
    copilot.displayText ""
  end
  if item.beforeChallenge then
    item.beforeChallenge(item)
  end
  if not copilot.usingTTScallouts then
    copilot.sleep(200, 700)
    if prob(0.5) then
      copilot.sleep(200, 700)
    end
  end
  self:_playCallout(item.label)
  item.numRetries = -1
  return self:_awaitResponse(item)
end

function Checklist:_suspendVoiceCommands()
  if self.voiceCommandsSuspended then return end
  self.vcStates = {}
  for _, voiceCommand in pairs(Event.voiceCommands) do
    if voiceCommand:recognizer() == copilot.recognizer and not self.voiceCommands[voiceCommand] then
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

  if #self.items == 0 then return end

  if Checklist._currChecklist then
    if Checklist._currChecklist ~= self then
      self.trigger:activate()
    end
    return
  end

  Checklist._currChecklist = self
  self.didShowText = false

  if not copilot.getCallbackStatus(coroutine.running()) then
    error("Checklist.execute() must be called from a coroutine added via a copilot API", 2)
  end

  copilot.sleep(500, 3000)
  if copilot.calloutExists("checklists." .. self.label .. ".announce") then
    self:_playCallout "announce"
  end

  self:_suspendVoiceCommands()

  local completionStatus = "completed"

  local i = 1
  while i <= #self.items do
    local item = self.items[i]
    self._currItem = item
    self._currItemIdx = i
    local res = self:_executeItem(item)
    for _, vc in pairs(item.response) do
      vc:deactivate()
    end
    if res.res == "checklist_reset" then
      print("Resetting checklist: " .. self.displayLabel)
      resetCurrChecklist()
      return self:execute()
    elseif res.res == "checklist_cancel" then
      print("Checklist canceled: " .. self.displayLabel)
      completionStatus = "canceled"
      self.trigger:activate()
      break
    elseif res.res == "checklist_skip" then
      print("Skipping checklist: " .. self.displayLabel)
      completionStatus = "skipped"
      break
    elseif res.res == "checklist_continue" then 
      if not res.disableDefault and (res.acknowledge or item.acknowledge) then
        copilot.sleep(200, 1000)
        self:_playCallout(res.acknowledge or item.acknowledge)
      end
      i = i + 1
    elseif res.res == "checklist_repeat_prev" and i > 1 then
      i = i - 1
    elseif res.res == "item_skip" then
      i = i + 1
    else error "huh?" end
  end

  resetCurrChecklist()

  if completionStatus == "completed" then
    self:_playCallout "completed"
  end

  if self.didShowText then
    copilot.displayText ""
  end

  self.sayAgainVoiceCommand:deactivate()
  self.standbyVoiceCommand:deactivate()
  self.resumeVoiceCommand:deactivate()
  self.restartVoiceCommand:deactivate()

  self:_resumeVoiceCommands()

  return completionStatus

end

function Checklist:_insertItem(pos, item, replace)
  if self._currChecklist == self then
    error("Not allowed to add items while executing checklist", 3)
  end
  if replace then
    self:_removeItem(self.items[pos])
    self.items[pos] = item
  else
    assert(not self:getItem(item.label), "An item with this label already exists: " .. item.label)
    table.insert(self.items, pos, item)
  end
  if util.isType(item.response, VoiceCommand) then
    item.response = {response = item.response}
  end
  for _, vc in pairs(item.response) do
    assert(vc:recognizer() == copilot.recognizer)
    self:_incVcCount(vc)
  end
end

--- Add new item to the end of the checklist. Browse the lua files at *copilot\checklists* for examples.
---@tparam table item A table with the following fields (only `label` and `response` are required):
---@string item.label The name of the sound file inside *copilot\sounds\callouts\checklistLabel*
---@param item.response Either a VoiceCommand or a table in the `label=VoiceCommand` key=value format where label
---is a string that will be passed to item.onResponse. If `response` is a single voice command, it is converted to a table with one key: "response".
---@string[opt] item.displayLabel The name of the item that will be displayed in message windows and logs
---@string[opt] item.acknowledge The name of the sound file inside *copilot\sounds\callouts\checklistLabel* that will be played if the response to the challenge is correct. If absent, no callout is played.
---@tparam[opt] function item.onResponse A function that will be called following the response to decide whether the response was correct. It receives the following parameters:
---
--- 1. A check function. 
---
---    If it's called with a string as the single argument, the check is considered failed and the string describes the reason. 
---
---    If it's called with two arguments, the first argument is evaluated for truthiness: if the value is falsy, the check is considered failed and the second string argument describes the reason.
---
---    The reason string is used for logging and is displayed in a message window if display_fail=1.
---
---    The function returns a bool that indicates whether the check succeeded
---
--- 2. A <a href='..\libraries\VoiceCommand.html#Class_RecoResult'>RecoResult</a> object
---
--- 3. The response voice command label
---
--- 4. A table where you can set some flags to control what happens next. The only field available is "acknowledge", which overrides item.acknowledge (see the *flapSetting* item in *coplot\checklists\beforeTakeoff.lua* for an example).
--- This table also provides the function `didFail` which returns true if the check function failed at least once.
---
--- 5. The item. The response voice command can be accessed through item[label]
---@tparam[opt] function item.beforeChallenge A function to be called before the challenge. It receives the item itself as the only parameter.
function Checklist:appendItem(item)
  self:_insertItem(#self.items+1, item)
  return self
end

--- Gets item by its label
--- @string label
---@return The item
---@index It's index
function Checklist:getItem(label)
  for i, item in ipairs(self.items) do
    if item.label == label then
      return item, i
    end
  end
end

--- Replaces the item with the same label as item.label.
--- @param item Same as in `Checklist:appendItem`
---@return self
function Checklist:replaceItem(item)
  self:_insertItem(
    assert(select(2, self:getItem(item.label)), "No such item: " .. item.label), 
    item,
    true
  )
  return self
end

--- Inserts an item after the item with the given label
--- @string label Label of the item after which the new item is to be inserted
---@param item Same as in `Checklist:appendItem`
---@return self
function Checklist:insertItem(label, item)
  self:_insertItem(
    assert(select(2, self:getItem(label)), "No such item: " .. label) + 1, 
    item
  )
  return self
end

function Checklist:_removeItem(item)
  if self._currChecklist == self then
    error("Not allowed to remove items while executing checklist", 2)
  end
  for _, vc in pairs(item.response) do
    self:_decVcCount(vc)
  end
end

--- Removes the item with the given label
--- @string label 
---@return self
function Checklist:removeItem(label)
  for i, item in ipairs(self.items) do
    if item.label == label then
      self:_removeItem(item)
      table.remove(self.items, i)
      break
    end
  end
  return self
end

if not copilot.UserOptions.checklists.menu_keybind then return end

local checklistMenu = {
  {text = "Repeat previous item", action = "checklist_repeat_prev"},
  {text = "Skip current item",    action = "item_skip"},
  {text = "Restart checklist",    action = "checklist_reset"},
  {text = "Cancel checklist",     action = "checklist_cancel"},
  {text = "Skip checklist",       action = "checklist_skip"}
}

local textMenu = TextMenu.new()
textMenu:setTimeout(10)
local textMenuCoro

local function showMenu()

  local checklist, item, itemIdx = Checklist.currChecklist()
  
  if not checklist then
    textMenu:setMenu("No checklist is being executed", "", {"OK"}):show()
    return
  end

  local function hasItemChanged()
    if select(2, Checklist.currChecklist()) == item then
      return false
    end
    textMenu:setMenu("The current checklist item has changed", "", {"OK"}):show()
    return true
  end

  local prompt = itemInfo(checklist, item, itemIdx)

  local menuItems = table.map(checklistMenu, function(menuItem) return menuItem.text end)
  local repeatPrevAvailable = itemIdx > 1

  if not repeatPrevAvailable then
    menuItems[1] = "Repeat previous item (unavailable)"
  end

  menuItems[#menuItems+1] = "Cancel"

  textMenu:setMenu("Select action for the current checklist:", prompt, menuItems):show()

  local status, res, text = Event.waitForEvent(textMenu.event)
  local menuCanceled = res == #menuItems
  if status ~= TextMenuResult.OK or 
    menuCanceled or 
    hasItemChanged() or
    res == 1 and not repeatPrevAvailable then 
    return 
  end

  local action = checklistMenu[res].action

  textMenu:setMenu("Are you sure?", text .. ": " .. prompt, {"Yes", "Cancel"}):show()
  status, res = Event.waitForEvent(textMenu.event)
  if res == 1 and not hasItemChanged() then 
    Checklist.checklistEvent:trigger(action)
  end
end

Bind {
  key = copilot.UserOptions.checklists.menu_keybind,
  onPress = function() 
    copilot.removeCallback(textMenuCoro)
    textMenuCoro = copilot.addCoroutine(showMenu) 
  end
}