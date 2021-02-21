if false then module "FSL2Lua" end

local file = require "FSL2Lua.FSL2Lua.file"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

local atsuLog = {
  path = not FSL2LUA_STANDALONE 
    and ipc.readSTR(0x3C00, 256)
      :gsub("FSLabs\\SimObjects.+", "FSLabs\\" .. FSL:getAcType() .. "\\Data\\ATSU\\ATSU.log")
}

function atsuLog:get()
  return file.read(self.path) or ""
end

function atsuLog:getMACTOW()
  return tonumber(self:get():match(".+MACTOW%s+(%d+%.%d+)"))
end

function atsuLog:getTakeoffPacks()
  local packs = self:get():match(".+PACKS%s+(%a+)")
  return (packs == "OFF" and 0 or packs == "ON" and 1), packs
end

function atsuLog:getTakeoffFlaps()
  return self:get():match(".+%(F/L%).-FLAPS.-(%d)\n")
end

function atsuLog:test()
  self.path = self.path:gsub("ATSU.log", "test.log")
end

return atsuLog