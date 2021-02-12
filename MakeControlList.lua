ipc = {readLvar = function() end}
package.path = "Modules\\?.lua;Modules\\?\\init.lua"
MAKE_CONTROL_LIST = true
FSL2LUA_STANDALONE = true
local FSL = require "FSL2Lua"
local A319_IS_A320 = require "FSL2Lua.config".A319_IS_A320

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

local function makeList(table,tableName)
  local temp = {}
  for controlName, controlObj in pairs(table) do
    if type(controlObj) == "table" and controlObj.FSL_VC_control then
      local available = {}
      local UNAVAILABLE = -1
      local FULLY_AVAILABLE = 0
      local MANUAL = 1

      local function macroAvailable(type)
        if type == "A319" and A319_IS_A320 then type = "A320" end
        if controlObj[type].rectangle then
          if controlObj[type].manual then
            return MANUAL
          end
          return FULLY_AVAILABLE
        end
        return UNAVAILABLE
      end

      if controlObj.FSControl then
        available = {A319 = FULLY_AVAILABLE, A320 = FULLY_AVAILABLE, A321 = FULLY_AVAILABLE}
      else
        available.A321 = macroAvailable "A321"
        available.A320 = macroAvailable "A320"
        available.A319 = macroAvailable "A319"
      end
      if available.A319 ~= UNAVAILABLE 
      or available.A320 ~= UNAVAILABLE 
      or available.A321 ~= UNAVAILABLE then
        local class = getmetatable(controlObj).__class
        local classLink = string.format("<a href='../libraries/FSL2Lua.html#Class_%s'>%s</a>", class, class)
        line = tableName .. "." .. controlName:gsub("_", "\\_")  .. "\n> Class: " .. classLink .. "\n"

        local allAvailable = true

        for _, v in ipairs{"A319", "A320", "A321"} do 
          if available[v] ~= FULLY_AVAILABLE then
            allAvailable = false
            line = line .. "\n\n>" .. v .. ": "
            if available[v] == MANUAL then
              line = line .. "no Lvar"
            elseif available[v] == UNAVAILABLE then
              line = line .. "unavailable"
            end
          end
        end

        if not allAvailable then
          line = line .. "\n"
        end
        
        if controlObj.posn then
          line = line .. "\n> Positions: "
          for pos in pairsByKeys(controlObj.posn) do
            if pos == pos:upper() then line = line .. "\"" .. pos:upper():gsub("_", "\\_") .. "\", " end
          end
          if line:sub(#line-1,#line-1) == "," then line = line:sub(1, #line-2) end
          line = line .. "\n"
        end
      end
    end
    if line then temp[line] = "" end
  end
  for line in pairsByKeys(temp) do
    io.write(line .. "\n")
  end
end

io.write("# FSLabs cockpit controls\nSee `FSL2Lua` on how to use these <br><br>")
makeList(FSL,"FSL")
makeList(FSL.FO, "FSL.FO")
makeList(FSL.CPT, "FSL.CPT")