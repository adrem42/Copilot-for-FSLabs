#include "FSL2LuaScript.h"
#include "JoystickManager.h"
#include "Copilot.h"

void FSL2LuaScript::initLuaState(sol::state_view lua)
{
	Joystick::makeLuaBindings(lua, joystickManager);
	LuaPlugin::initLuaState(lua);
	lua["muteCopilot"] = [] { copilot::onMuteKey(true); };
	lua["unmuteCopilot"] = [] { copilot::onMuteKey(false); };
}

void FSL2LuaScript::run() 
{

	joystickManager = std::make_shared<JoystickManager>();
	Joystick::addJoystickManager(joystickManager);
	LuaPlugin::run();

	auto joystickEvents = joystickManager->getEvents();
	size_t numEvents = joystickEvents.size() + 1;
	HANDLE* events = new HANDLE[numEvents]();
	for (size_t i = 0; i < joystickEvents.size(); ++i)
		events[i] = joystickEvents.at(i);
	events[numEvents - 1] = keyBindManager->queueEvent;

	while (true) {

		try {

			while (true) {

				DWORD eventIdx = WaitForMultipleObjects(numEvents, events, false, INFINITE);
				if (eventIdx == numEvents - 1)
					keyBindManager->consumeEvents();
				else
					joystickManager->onEvent(eventIdx);
			}

		} catch (sol::error& err) {
			onError(err);
		}

	}

	
}

void FSL2LuaScript::stopThread()
{
	Joystick::removeJoystickManager(joystickManager);
	LuaPlugin::stopThread();
}