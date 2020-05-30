#pragma warning(disable:4996)

#include "../lua515/include/lua.hpp"
#include <sol/sol.hpp>
#include <chrono>
#include "../HttpRequest/HttpRequest.h"
#include "../Copilot/versioninfo.h"

int HttpRequest::receiveTimeout = 0;
auto startTime = std::chrono::system_clock::now();

int elapsedTime(lua_State* L)
{
    lua_pushnumber(L, std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now() - startTime).count());
    return 1;
}

extern "C"
__declspec(dllexport) int luaopen_FSL2LuaDLL(lua_State * L)
{
    sol::state_view lua(L);

    auto HttpRequestType = lua.new_usertype<HttpRequest>("HttpRequest",
                                  sol::constructors<HttpRequest(const std::string&)>());
    HttpRequestType["get"] = &HttpRequest::get;
    HttpRequestType["setPort"] = &HttpRequest::setPort;
    HttpRequestType["lastError"] = &HttpRequest::lastError;

    auto McduType = lua.new_usertype<Mcdu>("McduHttpRequest",
                           sol::constructors<HttpRequest(int, int)>());
    McduType["getString"] = &Mcdu::getString;
    McduType["getRaw"] = &Mcdu::getRaw;
    McduType["setPort"] = &Mcdu::setPort;
    McduType["lastError"] = &Mcdu::lastError;

    lua["elapsedTime"] = &elapsedTime;
    lua["_FSL2LUA_VERSION"] = COPILOT_VERSION;
    return 0;
}
