local function defaultInit(i) return i end

function table.init(...)
  local t = {}
  if select("#", ...) == 2 then
    local initFunc = select(2, ...) or defaultInit
    for i = 1, select(1, ...) do
      t[i] = initFunc(i)
    end
  else
    local initFunc = select(4, ...) or defaultInit
    for i = select(1, ...), select(2, ...), select(3, ...) do
      t[#t+1] = initFunc(i)
    end
  end
  return t
end

function table.map(t, transform) 
  local out = {}
  for i, v in ipairs(t) do
    out[i] = transform(v)
  end
  return out
end

function table.mapIndexed(t, transform)
  local out = {}
  for i, v in ipairs(t) do
    out[i] = transform(i, v)
  end
  return out
end

function table.mapKeys(t, transform)
  local out = {}
  for k, v in pairs(t) do
    out[transform(k)] = v
  end
  return out
end

function table.mapValues(t, transform)
  local out = {}
  for k, v in pairs(t) do
    out[k] = transform(v)
  end
  return out
end

function table.mapPairs(t, transform)
  local out = {}
  for k, v in pairs(t) do
    local outK, outV = transform(k, v)
    out[outK] = outV
  end
  return out
end

function table.filter(t, pred)
  local out = {}
  for _, v in ipairs(t) do
    if pred(v) then 
      out[#out+1] = v 
    end
  end
  return out
end

function table.pack(...)
  return {n = select("#", ...), ...}
end

function table.unpack(t, i, j)
  return unpack(t, i or 1, j or t.n)
end