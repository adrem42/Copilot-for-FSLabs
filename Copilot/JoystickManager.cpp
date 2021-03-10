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

void JoystickManager::onNewDataAvailable(size_t eventIdx)
{
	auto& joystick = joysticks.at(eventIdx % (joysticks.size()));

	if (eventIdx < joysticks.size())
		joystick->getData();
	else
		joystick->onButtonRepeatTimer();
}

void JoystickManager::enqueueButtonEvent(ButtonEvent&& event)
{
	buttonEvents.emplace(std::move(event));
}

void JoystickManager::enqueueAxisEvent(AxisEvent&& event)
{
	axisEvents.emplace(std::move(event));
}

bool JoystickManager::hasEvents()
{
	return !buttonEvents.empty() || !axisEvents.empty();
}

void JoystickManager::dispatchEvents()
{
	while (buttonEvents.size()) {
		ButtonEvent event = buttonEvents.front();
		buttonEvents.pop();
		event.callback(event.buttonNum, event.action, event.timestamp);
	}
	while (axisEvents.size()) {
		AxisEvent event = axisEvents.front();
		axisEvents.pop();
		event.callback(event.value);
	}
}