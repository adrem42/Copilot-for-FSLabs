return {

  read = function(path)
    local file = io.open(path)
    if file then
      io.input(file)
      local s = io.read("*all")
      file:close()
      return s
    end
  end,

  write = function(path, str, method)
    local file = io.open(path, method or "a")
    file:write(str)
    file:close()
  end,

  create = function(path) io.open(path,"w"):close() end,

  exists = function(path)
    local file = io.open(path)
    if file then
      file:close()
      return true
    end
    return false
  end

}