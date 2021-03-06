#include "KeyBindManager.h"
#include "Keyboard.h"

using namespace Keyboard;

KeyBindManager::ShiftMapping KeyBindManager::shiftMapping{
    {TAB,           1 << 1},
    {SHIFT,         1 << 2},
    {CTRL,          1 << 3},
    {RIGHT_CTRL,    1 << 4},
    {ALT,           1 << 5},
    {RIGHT_ALT,     1 << 6},
    {WINDOWS,       1 << 7},
    {RIGHT_WINDOWS, 1 << 8},
    {APPS,          1 << 9},
    {RIGHT_APPS,    1 << 10},
};

void KeyBindManager::addBind(Keyboard::KeyCode keyCode, Keyboard::EventType event, Callback callback, ShiftValue shiftValue)
{
    auto& key = bindMap[shiftValue][keyCode];

    switch (event) {
        case EventType::Press:
            key.onPress.push_back(callback);
            break;
        case EventType::PressRepeat:
            key.onPressRepeat.push_back(callback);
            break;
        case EventType::Release:
            key.onRelease.push_back(callback);
            break;
    }
}

KeyBindManager::ShiftValue KeyBindManager::calculateShiftValue(std::vector<Keyboard::KeyCode> keyCodes)
{
    auto shiftValue = KeyBindManager::NO_SHIFTS;
    for (auto keyCode : keyCodes) {
        shiftValue |= KeyBindManager::shiftMapping[keyCode];
    }
    return shiftValue;
}

void KeyBindManager::addBind(Keyboard::KeyCode keyCode, Keyboard::EventType event, Callback callback)
{
    addBind(keyCode, event, callback, NO_SHIFTS);
}

void KeyBindManager::removeBind(
    Keyboard::KeyCode keyCode, Keyboard::EventType event,
    Callback callbackToRemove, std::vector<Keyboard::KeyCode> shifts
)
{
    auto it = bindMap.find(calculateShiftValue(shifts));
    if (it != bindMap.end()) {
        auto keyIt = it->second.find(keyCode);
        if (keyIt != it->second.end()) {
            auto& key = keyIt->second;
            std::vector<Callback>* callbacks = nullptr;

            switch (event) {
                case EventType::Press:
                    callbacks = &key.onPress;
                    break;
                case EventType::PressRepeat:
                    callbacks = &key.onPressRepeat;
                    break;
                case EventType::Release:
                    callbacks = &key.onRelease;
                    break;
            }
            
            if (callbacks) {
                callbacks->erase(std::find_if(callbacks->begin(), callbacks->end(), [&](Callback& callback) {
                    return callback.target<Callback>() == callbackToRemove.target<Callback>();
                }), callbacks->end());
            }

        }
    }
}

void KeyBindManager::addBind(
    Keyboard::KeyCode keyCode, Keyboard::EventType event,
    Callback callback, std::vector<Keyboard::KeyCode> shifts
)
{
    addBind(keyCode, event, callback, calculateShiftValue(shifts));
}

bool KeyBindManager::onKeyEvent(KeyCode keyCode, EventType event, Timestamp timestamp)
{
    {
        auto it = shiftMapping.find(keyCode);

        if (it != shiftMapping.end()) {
            switch (event) {
                case EventType::Press:
                    currShifts |= it->second;
                    break;
                case EventType::Release:
                    for (auto& [_, key] : bindMap[currShifts]) {
                        key.state = KeyState::Released;
                    }
                    currShifts &= ~it->second;
                    break;
            }
            return false;
        }
    }
    
    std::lock_guard<std::mutex> lock(queueMutex);

    auto& keys = bindMap[currShifts];

    auto it = keys.find(keyCode);

    std::vector<Callback>* callbacks = nullptr;

    if (it != keys.end()) {
        auto& key = it->second;
        switch (event) {

            case EventType::Press:

                switch (key.state) {

                    case KeyState::Depressed:
                        if (!key.onPressRepeat.empty())
                            callbacks = &key.onPressRepeat;
                        break;

                    case KeyState::Released:
                        if (!key.onPress.empty())
                            callbacks = &key.onPress;
                        break;
                }

                key.state = KeyState::Depressed;
                break;

            case EventType::Release:
                if (!key.onRelease.empty())
                    callbacks = &key.onRelease;
                key.state = KeyState::Released;
                break;
        }
    }

    if (callbacks) {
        for (auto& callback : *callbacks) {
            eventQueue.emplace_back(Event{timestamp, callback});
        }
        SetEvent(queueEvent);
        return true;
    }

    return false;
}

void KeyBindManager::consumeEvents()
{
    std::vector<Event> queue;
    {
        std::lock_guard<std::mutex> lock(queueMutex);
        queue.assign(eventQueue.begin(), eventQueue.end());
        eventQueue = std::vector<Event>();
    }
    for (auto& event : queue) {
        event.callback(event.timestamp);
    }
}

void KeyBindManager::makeLuaBindings(sol::state_view lua, std::shared_ptr<KeyBindManager> manager)
{
    using namespace Keyboard;
    lua["__addKeyBind"] = [manager](
        KeyCode keyCode, EventType event,
        Callback callback, std::vector<KeyCode> shifts
        ) {
        manager->addBind(keyCode, event, callback, shifts);
    };
    lua["__removeKeyBind"] = [manager](
        KeyCode keyCode, EventType event,
        Callback callback, std::vector<KeyCode> shifts
        ) {
        manager->removeBind(keyCode, event, callback, shifts);
    };
    lua.new_enum<Keyboard::EventType>(
        "KeyEventType",
        { 
            {"Press", EventType::Press },
            {"PressRepeat", EventType::PressRepeat },
            {"Release", EventType::Release }
        }
    );
}