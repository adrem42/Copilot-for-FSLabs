#pragma once
#include <Windows.h>
#include <unordered_map>
#include <vector>
#include <memory>

class KeyBindManager;

namespace Keyboard {

	using KeyCode = uint16_t;
	using Timestamp = size_t;

	using ShiftValue = uint16_t;
	static constexpr ShiftValue NO_SHIFTS = 0;
	using ShiftMapping = std::unordered_map<Keyboard::KeyCode, ShiftValue>;

	const KeyCode TAB = 9;
	const KeyCode SHIFT = 16;
	const KeyCode CTRL = 17;
	const KeyCode RIGHT_CTRL = 17 + 0xFF;
	const KeyCode ALT = 18;
	const KeyCode RIGHT_ALT = 18 + 0xFF;
	const KeyCode WINDOWS = 92;
	const KeyCode RIGHT_WINDOWS = 92 + 0xFF;
	const KeyCode APPS = 93;
	const KeyCode RIGHT_APPS = 93 + 0xFF;

	extern ShiftMapping shiftMapping;

	enum class EventType {
		Press, PressRepeat, Release, None
	};
	
	void addKeyBindManager(std::shared_ptr<KeyBindManager>);
	void removeKeyBindManager(std::shared_ptr<KeyBindManager>);

	bool onKeyEvent(UINT, WPARAM, LPARAM);
};