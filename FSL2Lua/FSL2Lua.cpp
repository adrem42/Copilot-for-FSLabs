#pragma warning(disable:4996)

extern "C"
{
#include "../lua515/include/lua.h"
#include "../lua515/include/lauxlib.h"
#include "../lua515/include/lualib.h"
}

#include <sol/sol.hpp>
#include "../HttpRequest/HttpRequest.h"

extern "C"
__declspec(dllexport) int luaopen_FSL2LuaDLL(lua_State * L)
{
    sol::state_view lua(L);

    sol::usertype<HttpRequest> HttpRequestType = lua.new_usertype<HttpRequest>("HttpRequest", sol::constructors<HttpRequest(const std::string&, int, const std::string&)>());
    HttpRequestType["get"] = &HttpRequest::get;
    HttpRequestType["setPort"] = &HttpRequest::setPort;

    return 0;
}
