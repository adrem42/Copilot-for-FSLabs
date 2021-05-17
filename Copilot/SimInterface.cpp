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

HWND SimInterface::p3dWnd;
HWND copilotWnd;
using namespace P3D;

const size_t MSG_FIRE_MOUSE_RECTANGLE = WM_APP + 0;

bool _firingMouseMacro = false;

std::mutex suppressCursorMutex;
bool cursorSuppressed = false;
size_t suppressCursorTimeout = 0;

LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
{
    switch (uMsg) {

       case MSG_FIRE_MOUSE_RECTANGLE: 
            _firingMouseMacro = true;
            copilot::GetWindowPluginSystem()->FireMouseRectClick(wParam, (MOUSE_CLICK_TYPE)lParam);
            _firingMouseMacro = false;
            break;

        case WM_TIMER: {
            std::unique_lock<std::mutex> lock(suppressCursorMutex);
            if (cursorSuppressed) {
                if (GetTickCount64() > suppressCursorTimeout) {
                    cursorSuppressed = false;
                    lock.unlock();
                    SimInterface::sendFSControl(66587, 79001);
                }
            }
        }
        break;
    }
    return DefWindowProc(hwnd, uMsg, wParam, lParam);
}

bool SimInterface::firingMouseMacro()
{
    return _firingMouseMacro;
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
    SetTimer(copilotWnd, NULL, 1000, NULL);
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

    void suppressCursor()
    {
        std::unique_lock<std::mutex> lock(suppressCursorMutex);
        suppressCursorTimeout = GetTickCount64() + 3000;
        if (!cursorSuppressed) {
            cursorSuppressed = true;
            lock.unlock();
            SimInterface::sendFSControl(66587, 79000);
        }
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