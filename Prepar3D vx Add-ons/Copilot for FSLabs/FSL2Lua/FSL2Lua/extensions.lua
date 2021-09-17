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

function table.keys(t)
  local out = {}
  for k in pairs(t) do
    out[#out+1] = k
  end
  return out
end

function table.values(t)
  local out = {}
  for _, v in pairs(t) do
    out[#out+1] = v
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

table.unpack = unpack

function table.size(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

function table.find(t, value)
  for i, val in ipairs(t) do
    if val == value then
      return i
    end
  end
end

function pairsByKeys (t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0      -- iterator variable
  local iter = function ()   -- iterator function
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end