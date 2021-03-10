#pragma once
#include "LuaPlugin.h"
#include "Joystick.h"
#include "Button.h"

class FSL2LuaScript : public LuaPlugin {

protected:

	std::shared_ptr<KeyBindManager> keyBindManager = nullptr;
	std::shared_ptr<JoystickManager> joystickManager = nullptr;

	struct Events {
		HANDLE * events;
		size_t numEvents;
		size_t KEYBOARD_EVENT;
		size_t JOYSTICK_EVENT_MIN;
		size_t JOYSTICK_EVENT_MAX;
		size_t SHUTDOWN_EVENT;
	};

	virtual void initLuaState(sol::state_view lua) override;

	Events createEvents();

	void onEvent(Events& events, DWORD eventIdx);

public:

	using LuaPlugin::LuaPlugin;
	virtual void run() override;
	virtual void stopThread() override;

	virtual ~FSL2LuaScript();
};