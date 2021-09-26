
local M = {}

function M.partial(func, ...)
  local boundArgs = table.pack(...)
  return function(...)
    local n = select("#", ...)
    local args = {n = boundArgs.n + n}
    for i = 1, boundArgs.n do
      args[i] = boundArgs[i]
    end
    for i = 1, n do
      args[boundArgs.n + i] = select(i, ...)
    end
    func(table.unpack(args, 1, args.n))
  end
end

return M