local util = require "FSL2Lua.FSL2Lua.util"

local BindMeta = {}
BindMeta.__index = BindMeta
local funcCount = 0

function BindMeta:destroy()
  if not self.globalFuncs then return end
  for _, funcName in ipairs(self.globalFuncs) do
    event.cancel(funcName)
    _G[funcName] = nil
  end
  self.globalFuncs = nil
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