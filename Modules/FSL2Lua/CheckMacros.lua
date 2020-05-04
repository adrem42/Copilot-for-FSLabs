local FSL = require "FSL2Lua"

local checked = {}
local missing = {}

local function checkControl(control)
  if type(control) == "table" and control.FSL_VC_control and control.checkMacro then
    if control.rectangle then
      if not control:checkMacro() then
        print("The macro of control " .. control.LVar .. " appears to be invalid")
      end
    elseif not control.FSControl then
      table.insert(missing, control)
    end
  end
end

local function checkMacros(table)
  for _, control in pairs(table) do
    if type(control) == "table" and control.LVar and control.LVar:lower():find("guard") then
      checkControl(control)
      checked[control] = true
    end
  end

  for _, control in pairs(table) do
    if not checked[control] then checkControl(control) end
  end
end

print "------------------------------------------------------"
print "Checking macros!"

checkMacros(FSL)
checkMacros(FSL.CPT)
checkMacros(FSL.FO)

--print("The following controls are missing rectangles:")
--for _, control in ipairs(missing) do print(control.LVar) end

print "Finished checking macros!"