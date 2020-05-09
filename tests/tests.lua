package.path = "C:\\Users\\Peter\\AppData\\Roaming/luarocks/share/lua/5.1/?.lua;C:\\Users\\Peter\\AppData\\Roaming/luarocks/share/lua/5.1/?/init.lua;" .. package.path
package.cpath = "C:\\Users\\Peter\\AppData\\Roaming/luarocks/lib/lua/5.1/?.dll;" .. package.cpath

function print(...) copilot.logger:info(...) end
io.write = print

require 'busted.runner'()

describe("Event class", function()

  it("can add and run actions", function()
    local args = {"foo", "bar", 1234}
    local event = Event:new()
    local normal = spy.new(function(_event, ...)
      assert.True(_event == event)
      assert.are.same(args, {...})
      assert.is_nil(coroutine.running())
    end)
    assert.True(event:getActionCount() == 0)
    event:addAction(normal)
    assert.True(event:getActionCount() == 1)
    event:trigger(unpack(args))
    assert.spy(normal).was_called(1)
    event:trigger(unpack(args))
    assert.spy(normal).was_called(2)
  end)

  it("can run action callbacks as coroutines", function()
    local args = {"foo", "bar", 1234}
    local event = Event:new()
    local coro = spy.new(function(_event, ...)
      assert.True(_event == event)
      assert.are.same({...}, args)
      assert.True(type(coroutine.running()) == "thread")
      coroutine.yield()
    end)
    local action = event:addAction(coro, "runAsCoroutine")
    assert.True(event:getActionCount() == 1)
    assert.False(action:isThreadRunning())
    event:trigger(unpack(args))
    assert.spy(coro).was_called(1)
    assert.True(action:isThreadRunning())
    Event.resumeThreads()
    assert.False(action:isThreadRunning())
  end)

  it("can add one-off actions", function()
    local event = Event:new()
    local s = spy.new()
    local s1 = spy.new()
    event:addOneOffAction(s)
    event:addOneOffAction(s)
    event:addAction(s1)
    event:addAction(s1)
    event:trigger()
    assert.spy(s).was_called(2)
    assert.spy(s1).was_called(2)
    event:trigger()
    assert.spy(s).was_called(2)
    assert.spy(s1).was_called(4)
  end)

  it("can stop coroutine actions", function()
    local event = Event:new()
    local action = event:addAction(function() while true do coroutine.yield() end end, "runAsCoroutine")
    event:trigger()
    assert.True(action:isThreadRunning())
    action:stopCurrentThread()
    assert.False(action:isThreadRunning())

    local event2 = Event:new()
    action:stopOn(event2)
    event:trigger()
    assert.True(action:isThreadRunning())
    event2:trigger()
    assert.False(action:isThreadRunning())
  end)

  it("can remove actions", function() 
    local event = Event:new()
    local s = spy.new()
    local action1 = event:addAction(s)
    local action2 = Action:new(s)
    event:addAction(action2)
    assert.True(event:getActionCount() == 2)
    event:removeAction(action1)
    event:removeAction(action2)
    event:trigger()
    assert.True(event:getActionCount() == 0)
    assert.spy(s).was_called(0)
    
  end)

  it("lets you define order of actions", function()
    local event = Event:new()

    local res = {}

    local second = event:addAction(function() 
      assert.has_error(function() Event:sortActions() end)
      table.insert(res, 2) 
    end)
    local first = event:addAction(function() table.insert(res, 1) end)
    local fourth = event:addAction(function() table.insert(res, 4) end)
    local third = event:addAction(function() table.insert(res, 3) end)

    event:setActionOrder(first):before(second)
    event:setActionOrder(second):before(third)
    event:setActionOrder(third):before(fourth)

    event:trigger()

    assert.are.same(res, {1, 2, 3, 4})

    res = {}

    event = Event:new()
    event:addAction(second)
    event:addAction(first)
    event:addAction(fourth)
    event:addAction(third)
    
    event:setActionOrder(first):front()
    event:setActionOrder(fourth):back()
    event:setActionOrder(second):after(first):before(third)

    event:trigger()

    assert.are.same(res, {1, 2, 3, 4})

    ----------------------------------------------------------

    res = {}

    event = Event:new()
    second = event:addAction(function()
      for _ = 1, 4 do coroutine.yield() end
      table.insert(res, 2)
    end, "runAsCoroutine")
    first = event:addAction(function()
      for _ = 1, 5 do coroutine.yield() end
      table.insert(res, 1)
    end, "runAsCoroutine")
    fourth = event:addAction(function()
      table.insert(res, 4)
    end, "runAsCoroutine")
    third = event:addAction(function()
      for _ = 1, 3 do coroutine.yield() end
      table.insert(res, 3)
    end, "runAsCoroutine")
    
    event:setActionOrder(first):front(false)
    event:setActionOrder(fourth):back(false)
    event:setActionOrder(second):after(first, false):before(third, false)

    event:trigger()

    for _ = 1, 20 do Event.resumeThreads() end

    assert.are.same({4,3,2,1}, res)

    res = {}

    event:setActionOrder(first):front()
    event:setActionOrder(fourth):back()
    event:setActionOrder(second):after(first):before(third)

    event:trigger()

    for _ = 1, 20 do Event.resumeThreads() end

    assert.are.same({1, 2, 3, 4}, res)

  end)

  it("throws an error when there is a cycle in the action order", function()
    local event = Event:new()
    local noop = function() end

    local second = event:addAction(noop)
    local first = event:addAction(noop)
    local fourth = event:addAction(noop)
    local third = event:addAction(noop)

    event:setActionOrder(first):before(second)
    event:setActionOrder(second):before(third)
    event:setActionOrder(third):before(fourth)
    event:setActionOrder(fourth):before(third)

    assert.has_error(function() event:trigger() end)

  end)

end)
