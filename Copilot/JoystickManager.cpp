#include "JoystickManager.h"
#include "Joystick.h"
#include "Button.h"

std::vector<HANDLE> JoystickManager::getEvents()
{
	std::vector<HANDLE> events;
	for (auto& joystick : joysticks)
		events.push_back(joystick->bufferAvailableEvent);
	for (auto& joystick : joysticks)
		events.push_back(joystick->buttonRepeatTimerHandle);
	return events;
}

void JoystickManager::onEvent(size_t eventIdx)
{
	auto& joystick = joysticks.at(eventIdx % (joysticks.size()));

	if (eventIdx < joysticks.size())
		joystick->getData();
	else
		joystick->onButtonRepeatTimer();
}
