#pragma warning(disable:4996)


#include "lua.hpp"
#include <sol\sol.hpp>

#include "../HttpRequest/HttpRequest.h"
#include "../Copilot/versioninfo.h"
#include "Joystick.h"

int HttpRequest::receiveTimeout = 0;

extern "C"
__declspec(dllexport) int luaopen_FSL2Lua_FSL2Lua(lua_State * L)
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

    lua["_FSL2LUA_VERSION"] = COPILOT_VERSION;
   
    Joystick::makeLuaBindings(lua);
    return 0;
}
