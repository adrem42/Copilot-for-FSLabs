#include "Keyboard.h"
#include "Copilot.h"
#include <memory>
#include <vector>
#include <algorithm>
#include "KeyBindManager.h"

using namespace Keyboard;

std::vector<std::shared_ptr<KeyBindManager>> bindManagers;

Keyboard::ShiftMapping Keyboard::shiftMapping{
    {VK_TAB,           1 << 1},
    {VK_LSHIFT,        1 << 2},
    {VK_RSHIFT,        1 << 3},
    {VK_LCONTROL,      1 << 4},
    {VK_RCONTROL,      1 << 5},
    {VK_LMENU,         1 << 6},
    {VK_RMENU,         1 << 7},
    {VK_LWIN,          1 << 8},
    {VK_RWIN,          1 << 9},
    {VK_APPS,          1 << 10}
};

std::mutex mutex;

void Keyboard::addKeyBindManager(std::shared_ptr<KeyBindManager> manager)
{
    std::lock_guard<std::mutex> lock(mutex);
    bindManagers.push_back(manager);
}

void Keyboard::removeKeyBindManager(std::shared_ptr<KeyBindManager> manager)
{
    std::lock_guard<std::mutex> lock(mutex);
    bindManagers.erase(
        std::remove(bindManagers.begin(), bindManagers.end(), manager),
        bindManagers.end());
}

Keyboard::ShiftValue calculateShiftValue()
{
    Keyboard::ShiftValue shiftVal = 0;
    for (auto& [keyCode, mask] : shiftMapping) {
        bool isPressed = GetAsyncKeyState(keyCode) & 0x40000;
        if (isPressed)
            shiftVal |= mask;
    }
    return shiftVal;
}

bool Keyboard::onKeyEvent(UINT uMsg, WPARAM wParam, LPARAM lParam)
{

    bool consumed = false;

    KeyCode keyCode = wParam;
    bool extended = lParam & (1 << 24);
    if (extended) keyCode += 0xFF;

    Timestamp timestamp = GetTickCount64();
    EventType event = EventType::None;

    switch (uMsg) {

        case WM_KEYDOWN: case WM_SYSKEYDOWN: {
            event = EventType::Press ;
            break;
        }

        case WM_KEYUP: case WM_SYSKEYUP: {
            event = EventType::Release;
            break;
        }
    }

    if (event != EventType::None) {
        ShiftValue shiftVal = calculateShiftValue();
        std::lock_guard<std::mutex> lock(mutex);
        for (auto& manager : bindManagers) {
            if (manager->onKeyEvent(keyCode, shiftVal, event, timestamp)) {
                consumed = true;
            }
        }
    }

    //copilot::logger->debug("uMsg: {}, wParam: {}, extended: {}", uMsg, wParam, extended);

    return consumed;
}
