local util = require "FSL2Lua.FSL2Lua.util"

local FCU = {}

function FCU.init(port)
  FCU.request = HttpSession 
    and HttpSession:new("http://localhost:" .. (port or 8080) .."/FCU/Display", 0)
end

function FCU:getField(json, fieldName)
  return json:match(fieldName .. ".-([%d%s]+)"):gsub(" ","")
end

function FCU:get()
  local json
  while true do
    json = self.request:get()
    if json ~= "" then break
    else util.handleError(string.format("FCU HTTP request error %s, retrying...", self.request.lastError), 2) end
  end
  local SPD = self:getField(json, "SPD")
  local HDG = self:getField(json, "HDG")
  local ALT = self:getField(json, "ALT")
  return {
    SPD = tonumber(SPD),
    HDG = tonumber(HDG),
    ALT = tonumber(ALT),
    isBirdOn = json:find("HDG_VS_SEL\":false") ~= nil
  } 
end

return FCU