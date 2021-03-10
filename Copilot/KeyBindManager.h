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

	using ShiftValue = uint16_t;

	static constexpr ShiftValue NO_SHIFTS = 0;

	using ShiftMapping = std::unordered_map<Keyboard::KeyCode, ShiftValue>;
	static  ShiftMapping shiftMapping;
	ShiftValue currShifts = NO_SHIFTS;

	static constexpr Keyboard::KeyCode TAB = 9;
	static constexpr Keyboard::KeyCode SHIFT = 16;
	static constexpr Keyboard::KeyCode CTRL = 17;
	static constexpr Keyboard::KeyCode RIGHT_CTRL = 17 + 0xFF;
	static constexpr Keyboard::KeyCode ALT = 18;
	static constexpr Keyboard::KeyCode RIGHT_ALT = 18 + 0xFF;
	static constexpr Keyboard::KeyCode WINDOWS = 92;
	static constexpr Keyboard::KeyCode RIGHT_WINDOWS = 92 + 0xFF;
	static constexpr Keyboard::KeyCode APPS = 93;
	static constexpr Keyboard::KeyCode RIGHT_APPS = 93 + 0xFF;

	struct Event {
		Keyboard::Timestamp timestamp;
		Callback callback;
	};

	enum class KeyState {
		Depressed, Released
	};

	struct Key {
		KeyState state = KeyState::Released;
		std::vector<Callback> onPress;
		std::vector<Callback> onPressRepeat;
		std::vector<Callback> onRelease;
	};

	std::unordered_map<ShiftValue, std::unordered_map<Keyboard::KeyCode, Key>> bindMap;

	std::mutex queueMutex;
	std::queue<Event> eventQueue;

	void addBind(Keyboard::KeyCode, Keyboard::EventType, Callback, ShiftValue);

	ShiftValue calculateShiftValue(std::vector<Keyboard::KeyCode> keyCodes);

public:

	HANDLE queueEvent = CreateEvent(0, 0, 0, 0);

	void addBind(Keyboard::KeyCode, Keyboard::EventType, Callback, std::vector<Keyboard::KeyCode>);
	void addBind(Keyboard::KeyCode, Keyboard::EventType, Callback);

	void removeBind(Keyboard::KeyCode, Keyboard::EventType, Callback, std::vector<Keyboard::KeyCode>);

	bool onKeyEvent(Keyboard::KeyCode, Keyboard::EventType, Keyboard::Timestamp);

	void dispatchEvents();

	bool hasEvents();

	static void makeLuaBindings(sol::state_view, std::shared_ptr<KeyBindManager> manager);

};