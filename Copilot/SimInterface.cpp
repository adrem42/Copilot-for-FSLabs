#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include "SimInterface.h"
#include <IWindowPluginSystem.h>
#include "SimConnect.h"
#include "Copilot.h"
#include <memory>


HHOOK mouseHook = 0;
HWND p3dWnd;
HWND copilotWnd;
using namespace P3D;

LRESULT CALLBACK LowLevelMouseProc(int nCode, WPARAM wParam, LPARAM lParam)
{
    while (ShowCursor(true) < 0);
    UnhookWindowsHookEx(mouseHook);
    mouseHook = 0;
    return CallNextHookEx(0, nCode, wParam, lParam);
}

void hideCursor()
{
    CURSORINFO cursorInfo = {};
    cursorInfo.cbSize = sizeof(CURSORINFO);
    GetCursorInfo(&cursorInfo);
    if (!cursorInfo.flags) return;
    while (ShowCursor(false) > -1);
    if (!mouseHook)
        mouseHook = SetWindowsHookEx(WH_MOUSE_LL, LowLevelMouseProc, 0, 0);
}

const size_t MSG_FIRE_MOUSE_RECTANGLE = WM_APP + 0;
const size_t MSG_HIDE_CURSOR = WM_APP + 1;

LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
{

    switch (uMsg) {

        case MSG_FIRE_MOUSE_RECTANGLE:
            copilot::GetWindowPluginSystem()->FireMouseRectClick(wParam, (MOUSE_CLICK_TYPE)lParam);
            break;

        case MSG_HIDE_CURSOR:
            hideCursor();
            break;

    }

    return DefWindowProc(hwnd, uMsg, wParam, lParam);
}

namespace SimInterface {

    void createWindow()
    {
        HRESULT hr;
        p3dWnd = FindWindow("FS98MAIN", NULL);

        auto hInst = GetModuleHandle(NULL);

        WNDCLASSEX wcex = {};
        wcex.cbSize = sizeof(WNDCLASSEX);
        wcex.lpfnWndProc = WindowProc;
        wcex.hInstance = hInst;
        wcex.hIcon = NULL;
        wcex.lpszClassName = "FSL2Lua";

        RegisterClassEx(&wcex);

        copilotWnd = CreateWindowEx(
            0, wcex.lpszClassName, "Copilot", WS_CHILD,
            0, 0, 0, 0, p3dWnd, NULL, hInst, NULL
        );
    }

    void onSimShutdown()
    {
        CloseWindow(copilotWnd);
    }

    void fireMouseMacro(size_t rectId, unsigned short clickType)
    {
        SendMessage(copilotWnd, MSG_FIRE_MOUSE_RECTANGLE, rectId, clickType);
    }

    void hideCursor()
    {
        SendMessage(copilotWnd, MSG_HIDE_CURSOR, 0, 0);
    }

    void initSimConnect()
    {
        SimConnect_MapClientEventToSimEvent(SimConnect::hSimConnect, SimConnect::EVENT_HIDE_CURSOR, "FSL2Lua.hideCursor");
        SimConnect_AddClientEventToNotificationGroup(SimConnect::hSimConnect, 0, SimConnect::EVENT_HIDE_CURSOR);
        SimConnect_SetNotificationGroupPriority(SimConnect::hSimConnect, 0, SIMCONNECT_GROUP_PRIORITY_HIGHEST);
    }

    std::optional<double> readLvar(const std::string& name)
    {
        if (name.empty()) return 0;
        ID i = check_named_variable(name.c_str());
        if (i == -1) return {};
        return get_named_variable_value(i);
    }

    void writeLvar(const std::string& name, double value)
    {
        set_named_variable_value(check_named_variable(name.c_str()), value);
    }

    void createLvar(const std::string& name, double initialValue = 0)
    {
        ID i = check_named_variable(name.c_str());
        if (i != -1) return;
        register_named_variable(name.c_str());
        writeLvar(name, initialValue);
    }
}