local FSL
FSL = {
  CPT = {},
  FO = {},
  PF = {},
  AC_TYPES = {"A319", "A320", "A321"},
  _checkControl = function(control, acType)
    if acType then
      if control[acType].available == false then return "unavailable" end
      if control.FSControl then return "full" end
      if not control[acType].rectangle then error "wtf" end
      if control[acType].manual then return "manual" end
      return "full"
    end
    if control.FSControl then return true end
    for _, _type in ipairs(FSL.AC_TYPES) do
      if control[_type].available ~= false and control[_type].rectangle then 
        return true 
      end
    end
    return false
  end
}
return FSL