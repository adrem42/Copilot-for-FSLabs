local EventUtils = {}

function EventUtils.removeEventRef(obj, refType, ...)
  if refType == "all" then
    for _, _refType in pairs(obj.eventRefs) do
      for event, action in pairs(_refType) do
        event:removeAction(action)
        obj.eventRefs[_refType][event] = nil
      end
    end
  else
    for _, event in ipairs {...} do
      event:removeAction(obj.eventRefs[refType][event])
      obj.eventRefs[refType][event] = nil
    end
  end
end

function EventUtils.makeEventRef(obj, func, refType, ...)
  for _, event in ipairs {...}  do
    local a = event:addAction(func)
    obj.eventRefs[refType][event] = a
    if event.logMsg ~= Event.NOLOGMSG then
      a:addLogMsg(("'%s' '%s' on event '%s'"):format(refType, obj:toString(), event:toString()))
    end
  end
end

return EventUtils