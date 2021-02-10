#pragma warning(disable:4996)

#include <Windows.h>
#include <SimConnect.h>
#include <lua.hpp>
#include <sol.hpp>
#include <chrono>
#include "../HttpRequest/HttpRequest.h"
#include "../Copilot/versioninfo.h"
#include "Joystick.h"

int HttpRequest::receiveTimeout = 0;
HANDLE hSimConnect;
HHOOK mouseHook = 0;
const int EVENT_HIDE_CURSOR = 0;

LRESULT CALLBACK LowLevelMouseProc(int nCode, WPARAM wParam, LPARAM lParam)
{
    while (ShowCursor(true) < 0);
    UnhookWindowsHookEx(mouseHook);
    mouseHook = 0;
    return CallNextHookEx(0, nCode, wParam, lParam);
}

void CALLBACK MyDispatchProcDLL(SIMCONNECT_RECV* pData, DWORD cbData, void* pContext)
{
    switch (pData->dwID) {
        case SIMCONNECT_RECV_ID_EVENT:
            SIMCONNECT_RECV_EVENT* evt = (SIMCONNECT_RECV_EVENT*)pData;
            switch (evt->uEventID) {
                case EVENT_HIDE_CURSOR:
                    CURSORINFO cursorInfo = {};
                    cursorInfo.cbSize = sizeof(CURSORINFO);
                    GetCursorInfo(&cursorInfo);
                    if (!cursorInfo.flags) return;
                    while (ShowCursor(false) > -1);
                    if (!mouseHook)
                        mouseHook = SetWindowsHookEx(WH_MOUSE_LL, LowLevelMouseProc, 0, 0);
            }
    }
}

void initSimConnect()
{
    SimConnect_Open(&hSimConnect, "FSL2Lua", NULL, 0, NULL, 0);
    SimConnect_MapClientEventToSimEvent(hSimConnect, EVENT_HIDE_CURSOR, "FSL2Lua.hideCursor");
    SimConnect_AddClientEventToNotificationGroup(hSimConnect, 0, EVENT_HIDE_CURSOR);
    SimConnect_SetNotificationGroupPriority(hSimConnect, 0, SIMCONNECT_GROUP_PRIORITY_HIGHEST);
    SimConnect_CallDispatch(hSimConnect, MyDispatchProcDLL, 0);
}

extern "C"
__declspec(dllexport) int luaopen_FSL2LuaDLL(lua_State * L)
{
    if (!hSimConnect)
        initSimConnect();
    LoadLibrary(L"FSL2LuaDLL");
    
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

    auto startTime = std::chrono::system_clock::now();
    lua["elapsedTime"] = [startTime] {
        return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now() - startTime
        ).count();
    };
    lua["_FSL2LUA_VERSION"] = COPILOT_VERSION;
    lua["hideCursor"] = [] {
        SimConnect_TransmitClientEvent(
            hSimConnect, 0, EVENT_HIDE_CURSOR, 0,
            SIMCONNECT_GROUP_PRIORITY_HIGHEST, 
            SIMCONNECT_EVENT_FLAG_GROUPID_IS_PRIORITY
        );
    };

    lua["error"] = [](sol::this_state s) {
        lua_State* L = s.lua_state();
        int level = luaL_optint(L, 2, 1);
        lua_settop(L, 1);
        if (lua_isstring(L, 1) && level > 0) { 
            while (level > 0) {
                lua_Debug ar;
                if (lua_getstack(L, level, &ar)) {
                    lua_getinfo(L, "Sl", &ar);
                    if (ar.currentline > 0) { 
                        lua_pushfstring(L, "%s:%d: ", ar.short_src, ar.currentline);
                        break;
                    }
                }
                level--;
            }
            lua_pushvalue(L, 1);
            lua_concat(L, 2);
        }
        const char* errMsg = lua_tostring(L, -1);
        char buff[1024];
        sprintf(buff, "local err = [[LUA Error: %s]]; print(err); ipc.exit()", errMsg);
        lua_getglobal(L, "loadstring");
        lua_pushstring(L, buff);
        lua_call(L, 1, 1);
        lua_call(L, 0, 0);
    };
    
    Joystick::makeLuaBindings(lua);
    return 0;
}
