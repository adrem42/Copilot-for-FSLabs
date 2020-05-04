_ALLRECTANGLES = true

local FSL = require "FSL2Lua"

local name = "C:\\Users\\Peter\\source\\repos\\FSLabs Copilot\\topics\\listofcontrols.md"
io.open(name,"w"):close()
local file = io.open(name,"a")
io.input(file)
io.output(file)

function pairsByKeys (t, f)
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

function makeList(table,tableName)
  local temp = {}
  for controlName,controlObj in pairs(table) do
    if type(controlObj) == "table" then
      local rect = controlObj._rectangle
      local A321 = rect and rect.A321
      local A320 = rect and rect.A320
      if A321 or A320 or controlObj.FSControl then
          line = tableName .. "." .. controlName .. (not controlObj.FSControl and ((A321 and not A320 and " (A321 only)") or (A320 and not A321 and " (A319/A320 only)") or "") or "")
        if controlObj.posn then
          line = line .. "\n> Positions: "
          for pos in pairsByKeys(controlObj.posn) do
            if pos == pos:upper() then line = line .. "\"" .. pos:upper() .. "\", " end
          end
          if line:sub(#line-1,#line-1) == "," then line = line:sub(1, #line-2) end
        end
      end
    elseif type(controlObj) == "function" and not controlName:sub(1,1):find("%W") and not controlName:sub(1,1):find("%l") then
      --line = "> " .. tableName .. "." .. controlName 
    end
    if line then temp[line] = "" end
  end
  for line in pairsByKeys(temp) do
    io.write(line .. "\n\n")
  end
end

io.write("# FSLabs cockpit controls\nSee @{FSL2Lua} on how to use these<br><br><br>")
makeList(FSL,"FSL")
makeList(FSL.FO, "FSL.FO")
makeList(FSL.CPT, "FSL.CPT")
