local util = require "FSL2Lua.FSL2Lua.util"

local BindMeta = {}
BindMeta.__index = BindMeta
local funcCount = 0

if _COPILOT then
  function BindMeta:destroy()
    local function remove(event, callback)
      __removeKeyBind(self.keyBind.key, event, callback, self.keyBind.shifts)
    end
    if self.data.onPress then
      remove(KeyEventType.Press, self.data.onPress)
    end
    if self.data.onPressRepeat then
      remove(KeyEventType.PressRepeat, self.data.onPressRepeat)
    end
    if self.data.onRelease then
      remove(KeyEventType.Release, self.data.onRelease)
    end
  end
else
  function BindMeta:destroy()
    if not self.globalFuncs then return end
    for _, funcName in ipairs(self.globalFuncs) do
      if type(_G[funcName]) == "function" then
        event.cancel(funcName)
        _G[funcName] = nil
      end
    end
    self.globalFuncs = nil
  end
end

function BindMeta:addGlobalFunc(func)
  funcCount = funcCount + 1
  local funcName = "FSL2LuaGFunc" .. funcCount
  if util.isFuncTable(func) then _G[funcName] = function() func() end
  else _G[funcName] = func end
  self.globalFuncs[#self.globalFuncs+1] = funcName
  return funcName
end

function BindMeta:rebind()
  if self.globalFuncs then return end
  self.globalFuncs = {}
  if self.data.onPress then self:registerOnPressEvents() end
  if self.data.onRelease then self:registerOnReleaseEvents() end
end

return BindMeta