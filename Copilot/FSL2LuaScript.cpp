#include "FSL2LuaScript.h"
#include "JoystickManager.h"
#include "Copilot.h"

void FSL2LuaScript::initLuaState(sol::state_view lua)
{
	keyBindManager = std::make_shared<KeyBindManager>();
	Keyboard::addKeyBindManager(keyBindManager);
	KeyBindManager::makeLuaBindings(lua, keyBindManager);

	joystickManager = std::make_shared<JoystickManager>();
	Joystick::addJoystickManager(joystickManager);
	Joystick::makeLuaBindings(lua, joystickManager);

	lua["muteCopilot"] = [] { copilot::onMuteKey(true); };
	lua["unmuteCopilot"] = [] { copilot::onMuteKey(false); };

	lua.registry()["dispatchKeyboardEvents"] = [this] {
		keyBindManager->dispatchEvents();
	};

	lua.registry()["dispatchJoystickEvents"] = [this] {
		joystickManager->dispatchEvents();
	};


	LuaPlugin::initLuaState(lua);
}

FSL2LuaScript::Events FSL2LuaScript::createEvents()
{
	auto joystickEvents = joystickManager->getEvents();
	size_t numEvents = joystickEvents.size() + 2;
	HANDLE* events = new HANDLE[numEvents]();
	for (size_t i = 0; i < joystickEvents.size(); ++i)
		events[i] = joystickEvents.at(i);

	size_t KEYBOARD_EVENT = numEvents - 2;
	events[KEYBOARD_EVENT] = keyBindManager->queueEvent;

	size_t SHUTDOWN_EVENT = numEvents - 1;
	events[SHUTDOWN_EVENT] = shutdownEvent;

	Events e = {};

	e.events = events;
	e.numEvents = numEvents;
	e.JOYSTICK_EVENT_MIN = 0;
	e.JOYSTICK_EVENT_MAX = std::min<size_t>(joystickEvents.size() - 1, 0);
	e.KEYBOARD_EVENT = KEYBOARD_EVENT;
	e.SHUTDOWN_EVENT = SHUTDOWN_EVENT;

	return 	e;
}

void FSL2LuaScript::onEvent(Events& events, DWORD eventIdx)
{
	if (eventIdx == events.KEYBOARD_EVENT) {
		while (keyBindManager->hasEvents()) 
			callLuaFunction(lua.registry()["dispatchKeyboardEvents"]);
	} else {
		joystickManager->onNewDataAvailable(eventIdx);
		while (joystickManager->hasEvents()) 
			callLuaFunction(lua.registry()["dispatchJoystickEvents"]);
	}
}

void FSL2LuaScript::run() 
{
	LuaPlugin::run();

	auto events = createEvents();
	
	while (true) {
		DWORD res = WaitForMultipleObjects(events.numEvents, events.events, false, INFINITE);
		if (res == events.SHUTDOWN_EVENT) break;
		else onEvent(events, res);
	}
	
	delete events.events;
}

FSL2LuaScript::~FSL2LuaScript()
{
	Joystick::removeJoystickManager(joystickManager);
	Keyboard::removeKeyBindManager(keyBindManager);
}

void FSL2LuaScript::stopThread()
{
	Joystick::removeJoystickManager(joystickManager);
	Keyboard::removeKeyBindManager(keyBindManager);

	LuaPlugin::stopThread();
}