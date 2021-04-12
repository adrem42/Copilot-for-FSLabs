#include "KeyBindManager.h"
#include "Keyboard.h"

using namespace Keyboard;

void KeyBindManager::addBind(KeyCode keyCode, EventType event, Callback callback, ShiftValue shiftValue)
{
    std::lock_guard<std::mutex> lock(bindMapMutex);
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

Keyboard::ShiftValue KeyBindManager::calculateShiftValue(std::vector<KeyCode> keyCodes)
{
    auto shiftValue = NO_SHIFTS;
    for (auto keyCode : keyCodes) {
        shiftValue |= shiftMapping[keyCode];
    }
    return shiftValue;
}

void KeyBindManager::addBind(Keyboard::KeyCode keyCode, EventType event, Callback callback)
{
    addBind(keyCode, event, callback, NO_SHIFTS);
}

void KeyBindManager::removeBind(
    KeyCode keyCode, EventType event,
    Callback callbackToRemove, std::vector<KeyCode> shifts
)
{
    std::lock_guard<std::mutex> lock(bindMapMutex);
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
    KeyCode keyCode, EventType event,
    Callback callback, std::vector<KeyCode> shifts
)
{
    addBind(keyCode, event, callback, calculateShiftValue(shifts));
}

bool KeyBindManager::onKeyEvent(KeyCode keyCode, ShiftValue shiftVal, EventType event, Timestamp timestamp)
{
    
    std::lock_guard<std::mutex> lock(bindMapMutex);
    bool retVal = false;

    for (auto& [val, keys] : bindMap) {
        if (val == NO_SHIFTS && shiftVal != NO_SHIFTS)
            continue;
        if ((shiftVal & val) == val) {
            auto it = keys.find(keyCode);
            if (it == keys.end()) continue;
            auto& keyCallbacks = it->second;
            if (keyCallbacks.onPress.size()
                || keyCallbacks.onPressRepeat.size()
                || keyCallbacks.onRelease.size()) {
                retVal = true;
            }

            std::vector<Callback>* callbacks = nullptr;

            switch (event) {
                case EventType::Press:
                    if (keyCallbacks.onPress.size())
                        callbacks = &keyCallbacks.onPress;
                    break;
                case EventType::PressRepeat:
                    if (keyCallbacks.onPressRepeat.size())
                        callbacks = &keyCallbacks.onPress;
                    break;
                case EventType::Release:
                    if (keyCallbacks.onRelease.size())
                        callbacks = &keyCallbacks.onPress;
                    break;
            }
            if (callbacks) {
                std::lock_guard<std::mutex> lock(queueMutex);
                eventQueue.emplace(Event{ timestamp, callbacks });
                SetEvent(queueEvent);
            }
        }
    }

    return retVal;
}

void KeyBindManager::dispatchEvents()
{
    while (true) {
        std::unique_lock<std::mutex> lock(queueMutex);
        if (eventQueue.empty()) return;
        Event event = eventQueue.front();
        eventQueue.pop();
        lock.unlock();
        for (auto& callback : *event.callbacks)
            callback(event.timestamp);
    }
}

bool KeyBindManager::hasEvents()
{
    std::lock_guard<std::mutex> lock(queueMutex);
    return !eventQueue.empty();
}

void KeyBindManager::makeLuaBindings(sol::state_view lua, std::shared_ptr<KeyBindManager> manager)
{
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