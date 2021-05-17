#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include "SimConnect.h"
#include <memory>
#include <string>
#include <optional>
#include "Keyboard.h"

namespace SimInterface {

    bool init();

    void close();

    extern HWND p3dWnd;

    void fireMouseMacro(size_t rectId, unsigned short clickType);
    bool firingMouseMacro();

    void suppressCursor();

    std::optional<double> readLvar(const std::string&);

    void writeLvar(const std::string&, double);

    void createLvar(const std::string&, double = 0);

    __declspec(dllexport) void sendFSControl(size_t, size_t = 0);

    enum class KeyEvent {
        Press, Release
    };

    void sendKeyToSimWindow(SHORT keyCode, KeyEvent e);

}