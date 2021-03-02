#pragma once
#include "../HttpRequest/HttpRequest.h"
#include <sol/sol.hpp>
#include "MySimConnect.h"
#include "Misc.h"
#include <chrono>
#include "../Copilot/versioninfo.h"

int HttpRequest::receiveTimeout = 0;

void makeLuaBindings(sol::state_view lua)
{
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

    lua["mousemacro"] = [](size_t rectId, unsigned short clickType) {
        SendMessage(myWnd, WM_APP, rectId, clickType);
    };

    Joystick::makeLuaBindings(lua);
}