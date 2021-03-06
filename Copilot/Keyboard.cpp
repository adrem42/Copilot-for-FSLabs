#include "Keyboard.h"
#include "Copilot.h"
#include <memory>
#include <vector>
#include <algorithm>
#include "KeyBindManager.h"

using namespace Keyboard;

std::vector<std::shared_ptr<KeyBindManager>> bindManagers;

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
        std::lock_guard<std::mutex> lock(mutex);
        for (auto& manager : bindManagers) {
            if (manager->onKeyEvent(keyCode, event, timestamp)) {
                consumed = true;
            }
        }
    }

    //copilot::logger->debug("Keycode: {}, wParam: {}, Event: {}", keyCode, wParam, event);

    return consumed;
}
