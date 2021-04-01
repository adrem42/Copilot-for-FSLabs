#pragma once
#include <Windows.h>
#include <unordered_map>
#include <queue>
#include <memory>
#include "Keyboard.h"
#include <functional>
#include <mutex>
#include <sol/sol.hpp>
#include <bitset>

class KeyBind;

class KeyBindManager {

	using Callback = std::function<void(Keyboard::Timestamp)>;

	struct Event {
		Keyboard::Timestamp timestamp;
		std::vector<Callback>* callbacks;
	};
	
	enum class KeyState { Released, Depressed };

	struct Callbacks {
		std::vector<Callback> onPress;
		std::vector<Callback> onPressRepeat;
		std::vector<Callback> onRelease;
	};

	std::unordered_map<Keyboard::KeyCode, KeyState> keyStates;

	std::mutex bindMapMutex;
	std::unordered_map<Keyboard::ShiftValue, std::unordered_map<Keyboard::KeyCode, Callbacks>> bindMap;

	std::mutex queueMutex;
	std::queue<Event> eventQueue;

	void addBind(Keyboard::KeyCode, Keyboard::EventType, Callback, Keyboard::ShiftValue);
	Keyboard::ShiftValue calculateShiftValue(std::vector<Keyboard::KeyCode> keyCodes);

public:

	HANDLE queueEvent = CreateEvent(0, 0, 0, 0);

	void addBind(Keyboard::KeyCode, Keyboard::EventType, Callback, std::vector<Keyboard::KeyCode>);
	void addBind(Keyboard::KeyCode, Keyboard::EventType, Callback);

	void removeBind(Keyboard::KeyCode, Keyboard::EventType, Callback, std::vector<Keyboard::KeyCode>);

	bool onKeyEvent(Keyboard::KeyCode, Keyboard::ShiftValue shiftVal, Keyboard::EventType, Keyboard::Timestamp);

	void dispatchEvents();

	bool hasEvents();

	static void makeLuaBindings(sol::state_view, std::shared_ptr<KeyBindManager> manager);

};