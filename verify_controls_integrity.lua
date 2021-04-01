local check = pcall(require, "controls_check.saved_controls")

if not check then return {} end

check = require "controls_check.saved_controls"

package.path = package.path .. ";Prepar3D vx Add-ons\\Copilot for FSLabs\\?.lua;Prepar3D vx Add-ons\\Copilot for FSLabs\\?\\init.lua;Prepar3D vx Add-ons\\Copilot for FSLabs\\lua\\?.lua"
FSL2LUA_MAKE_CONTROL_LIST = true
local FSL = require "FSL2Lua.FSL2Lua.FSL2Lua"

local controls = {}

for _, v in pairs(FSL) do
  controls[v.name] = v
end

local failed = {"The following controls failed the check:"}

local count = 0

for k, v in pairs(check) do

  count = count + 1
  
  if not controls[k] then
    failed[#failed+1] = k
  elseif not controls[k].FSControl then
    for _, _type in ipairs(require "FSL2Lua.FSL2Lua.FSLinternal".AC_TYPES) do
      if v[_type] and not controls[k][_type].rectangle then
        failed[#failed+1] = k .. ": " .. _type
      end
    end
  end
end

if #failed > 1 then
  error(table.concat(failed, "\n"))
end

print ("Check successful, " .. count .. " controls in total")

return check