
local root = "Prepar3D vx Add-ons\\Copilot for FSLabs\\"
package.path = root .. "?.lua;" .. root .. "\\lua\\?.lua;" .. root .. "\\?\\init.lua"
FSL2LUA_MAKE_CONTROL_LIST = true
local FSL = require "FSL2Lua"
local AC_TYPES = require "FSL2Lua.FSL2Lua.FSLinternal".AC_TYPES
local path = "topics\\listofcontrols.md"
io.open(path,"w"):close()
local file = io.open(path,"a")
io.input(file)
io.output(file)

local function pairsByKeys (t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, function(a, b) 
    if tonumber(a) and tonumber(b) then
      return tonumber(a) < tonumber(b)
    else 
      return a:gsub("^>%s+", "") < b:gsub("^>%s+", "")
    end
  end)
  local i = 0 
  local iter = function ()
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end

local function makeList()
  local lines = {}
  local count = 0
  for _, control in ipairs(FSL) do
    count = count + 1
    local line

    local class = getmetatable(control).__class
    local classLink = string.format("<a href='../libraries/FSL2Lua.html#Class_%s'>%s</a>", class, class)
    line = control.name:gsub("_", "\\_")  .. "\n> Class: " .. classLink .. "\n"

    local allTypesAvailable = true

    if not allTypesAvailable then
      line = line .. "\n"
    end
    
    if control.posn then
      line = line .. "\n> Positions: "

      local positions = {}

      for pos in pairs(control.posn) do positions[#positions+1] = pos end
      table.sort(positions, function(pos1, pos2) return control.posn[pos1] < control.posn[pos2] end)

      for _, pos in ipairs(positions) do
        if pos == pos:upper() then line = line .. "\"" .. pos:upper():gsub("_", "\\_") .. "\", " end
      end
      if line:sub(#line-1,#line-1) == "," then line = line:sub(1, #line-2) end
      line = line .. "\n"
    end

    if line then lines[line] = "" end

  end

  for line in pairsByKeys(lines) do
    io.write(line .. "\n")
  end
end

io.write("# FSLabs cockpit controls\nSee `FSL2Lua` on how to use these <br><br>")
makeList()
