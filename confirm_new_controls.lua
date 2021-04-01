package.path = package.path .. ";Prepar3D vx Add-ons\\Copilot for FSLabs\\?.lua;Prepar3D vx Add-ons\\Copilot for FSLabs\\?\\init.lua"
FSL2LUA_STANDALONE = true
local old = require "verify_controls_integrity"
_FSL = require "FSL2Lua"
local FSL = require "FSL2Lua.FSL2Lua.FSL"
local file = require "FSL2Lua.FSL2Lua.file"
local serpent = require "FSL2Lua.libs.serpent"
local Control = require "FSL2Lua.FSL2Lua.Control"
local util = require "FSL2Lua.FSL2Lua.util"

local new = {}
local varnames = {}
local count = 0

for k, v in pairs(FSL) do
  if util.isType(v, Control) and not old[v.name] and not new[v.name] then
    local t = {}
    for _, _type in ipairs(require "FSL2Lua.FSL2Lua.FSLinternal".AC_TYPES) do
      local available = require "FSL2Lua.FSL2Lua.FSLinternal"._checkControl(v, _type)
      t[_type] = available == "unavailable" and false or true
    end
    new[v.name] = t
    varnames[k] = v.name
    count = count + 1
  end
end

FSL = dofile"Prepar3D vx Add-ons\\Copilot for FSLabs\\FSL2Lua\\FSL2Lua\\FSL.lua"

for k, v in pairs(varnames) do
  FSL[k].name = v
end

if count == 0 then
  print "No new controls!"
  return
end
print(FSL.PED_MCDU_KEY_ARPT)
print("Type 'yes' to confirm " .. count .. " new controls:")
print "---------------------------------------------------"
for k in pairs(new) do
  print(k)
end
print "---------------------------------------------------"

local answer = io.read()

if answer:lower() == "yes" then
  for k, v in pairs(new) do
    old[k] = v
  end
  file.write("controls_check\\saved_controls.lua", "return " .. serpent.block(old, {comment = false, sparse = false}),"w")
  local check = dofile "controls_check\\saved_controls.lua"
  for k, v in pairs(old) do
    for _type in pairs(v) do
      if v[_type] and not check[k][_type] then
        print(_type, k)
        error "something went wrong"
      end
    end
  end
  file.write("Prepar3D vx Add-ons\\Copilot for FSLabs\\FSL2Lua\\FSL2Lua\\FSL.lua", "return " .. serpent.block(FSL, {comment = false, sparse = false}),"w")
  require "verify_controls_integrity"
  print "New controls saved successfully!"
else
  print "Aborting..."
end