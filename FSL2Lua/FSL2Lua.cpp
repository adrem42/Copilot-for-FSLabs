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
    sol::usertype<Mcdu> McduType = lua.new_usertype<Mcdu>("McduHttpRequest", sol::constructors < Mcdu(int, int)>());
    McduType["get"] = &Mcdu::getFromLua;
    McduType["setPort"] = &Mcdu::setPort;
    return 1;
}
