local EventUtils = {}

function EventUtils.removeEventRef(obj, refType, ...)
  if refType == "all" then
    for _, refTable in pairs(obj.eventRefs) do
      for event, action in pairs(refTable) do
        event:removeAction(action)
      end
    end
  else
    for _, event in ipairs {...} do
      event:removeAction(obj.eventRefs[refType][event])
    end
  end
end

function EventUtils.makeEventRef(obj, func, refType, ...)
  for _, event in ipairs {...}  do
    obj.eventRefs[refType][event] = event:addAction(func)
  end
end

return EventUtils