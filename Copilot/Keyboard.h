#pragma once
#include <Windows.h>
#include <unordered_map>
#include <vector>
#include <memory>

class KeyBindManager;

namespace Keyboard {

	using KeyCode = uint16_t;
	using Timestamp = size_t;

	enum class EventType {
		Press, PressRepeat, Release, None
	};
	
	void addKeyBindManager(std::shared_ptr<KeyBindManager>);
	void removeKeyBindManager(std::shared_ptr<KeyBindManager>);

	bool onKeyEvent(UINT, WPARAM, LPARAM);
};