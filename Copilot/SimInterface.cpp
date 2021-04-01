#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include "SimInterface.h"
#include <IWindowPluginSystem.h>
#include <commctrl.h>
#include "SimConnect.h"
#include "Copilot.h"
#include "KeyBindManager.h"
#include <memory>

HHOOK mouseHook = 0;
HWND SimInterface::p3dWnd;
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

void createWindow()
{

    auto hInst = GetModuleHandle(NULL);

    WNDCLASSEX wcex = {};
    wcex.cbSize = sizeof(WNDCLASSEX);
    wcex.lpfnWndProc = WindowProc;
    wcex.hInstance = hInst;
    wcex.hIcon = NULL;
    wcex.lpszClassName = TEXT("FSL2Lua");

    RegisterClassEx(&wcex);

    copilotWnd = CreateWindowEx(
        0, wcex.lpszClassName, TEXT("Copilot"), WS_CHILD,
        0, 0, 0, 0, SimInterface::p3dWnd, NULL, hInst, NULL
    );
}

LRESULT Subclassproc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam, UINT_PTR uIdSubclass, DWORD_PTR dwRefData)
{
    switch (uMsg) {

        case WM_KEYDOWN: case WM_KEYUP: case WM_SYSKEYDOWN: case WM_SYSKEYUP:
            if (Keyboard::onKeyEvent(uMsg, wParam, lParam))
                return 0;
            break;

        case WM_CLOSE:
            copilot::onWindowClose();
            break;

        default:
            break;
    }

    return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

namespace SimInterface {

    bool init()
    {
        p3dWnd = FindWindow(TEXT("FS98MAIN"), NULL);
        SetWindowSubclass(p3dWnd, Subclassproc, 0, 0);
        createWindow();
        return true;
    }

    void close()
    {
        CloseWindow(copilotWnd);
        RemoveWindowSubclass(p3dWnd, Subclassproc, 0);
    }

    void fireMouseMacro(size_t rectId, unsigned short clickType)
    {
        SendMessage(copilotWnd, MSG_FIRE_MOUSE_RECTANGLE, rectId, clickType);
    }

    void hideCursor()
    {
        SendMessage(copilotWnd, MSG_HIDE_CURSOR, 0, 0);
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

    void createLvar(const std::string& name, double initialValue)
    {
        ID i = check_named_variable(name.c_str());
        if (i != -1) return;
        register_named_variable(name.c_str());
        writeLvar(name, initialValue);
    }

    void sendFSControl(size_t id, size_t param)
    {
        SendMessage(p3dWnd, WM_COMMAND, id, param);
    }

    void sendKeyToSimWindow(SHORT keyCode, KeyEvent e)
    {
        uint16_t winEvent = e == KeyEvent::Press ? WM_KEYDOWN : WM_KEYUP;
        SendMessage(p3dWnd, winEvent, keyCode, 0);
    }

}