#include "Keyboard.h"
#include "Copilot.h"
#include <memory>
#include <vector>
#include <algorithm>
#include "KeyBindManager.h"

using namespace Keyboard;

std::vector<std::shared_ptr<KeyBindManager>> bindManagers;

enum class KeyState { Released, Depressed };
std::unordered_map<Keyboard::KeyCode, KeyState> keyStates;

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
    {VK_APPS,          1 << 10},

    {VK_SHIFT,         1 << 11},
    {VK_MENU,          1 << 12},
    {VK_CONTROL,       1 << 13},
};

std::mutex mutex;

struct ShiftValues {
    Keyboard::ShiftValue withSides;
    Keyboard::ShiftValue withoutSides;
};

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

ShiftValue calculateShiftValue()
{
    ShiftValue value = NO_SHIFTS;
    for (auto& [keyCode, mask] : shiftMapping) {

        bool isPressed = GetAsyncKeyState(keyCode) & 0x40000;
        if (isPressed) 
            value |= mask;
    }
    return value;
}

bool Keyboard::onKeyEvent(UINT uMsg, WPARAM wParam, LPARAM lParam)
{

    bool consumed = false;

    KeyCode keyCode = wParam;
    bool extended = lParam & (1 << 24);
    if (extended) keyCode += 0xFF;

    Timestamp timestamp = GetTickCount64();
    EventType event = EventType::None;
    auto currKeyState = keyStates[keyCode];

    switch (uMsg) {

        case WM_KEYDOWN: case WM_SYSKEYDOWN: {
            switch (currKeyState) {
                case KeyState::Depressed:
                    event = EventType::PressRepeat;
                    break;
                case KeyState::Released:
                    event = EventType::Press;
                    break;
            }
            keyStates[keyCode] = KeyState::Depressed;
            break;
        }

        case WM_KEYUP: case WM_SYSKEYUP: {
            event = EventType::Release;
            keyStates[keyCode] = KeyState::Released;
            break;
        }
    }

    if (event != EventType::None) {
        auto shiftValue = calculateShiftValue();

        std::lock_guard<std::mutex> lock(mutex);
        for (auto& manager : bindManagers) {
            if (manager->onKeyEvent(keyCode, shiftValue, event, timestamp)) {
                consumed = true;
            }
        }
    }

    //copilot::logger->debug("uMsg: {}, wParam: {}, extended: {}", uMsg, wParam, extended);

    return consumed;
}
