#include "Button.h"

Joystick::Button::Button(uint16_t buttonNum, uint16_t dataIndex, std::shared_ptr<JoystickManager> manager)
	:buttonNum(buttonNum), dataIndex(dataIndex), manager(manager)
{
}

bool Joystick::Button::maybePress(size_t timestamp)
{
	if (state != ButtonState::Pressed) {
		onPress(timestamp);
		return !onPressRepeatCallbacks.empty();
	}
	return false;
}

void Joystick::Button::maybeRelease(size_t timestamp)
{
	if (state != ButtonState::Released)
		onRelease(timestamp);
}

void Joystick::Button::onPressRepeat(size_t timestamp)
{
	for (auto& callback : onPressRepeatCallbacks) {
		if (timestamp - callback.lastInvokationTime > static_cast<size_t>(callback.repeatInterval) - 2) {
			callback.lastInvokationTime = timestamp;
			manager->enqueueButtonEvent(
				JoystickManager::ButtonEvent{ 
					callback.callback, buttonNum, 
					EVENT_TYPE_REPEATED_PRESS, timestamp 
				}
			);
		}
	}
}

void Joystick::Button::onRelease(size_t timestamp)
{
	state = ButtonState::Released;
	for (auto& callback : onReleasecallbacks) {
		manager->enqueueButtonEvent(
			JoystickManager::ButtonEvent{ callback, buttonNum, EVENT_TYPE_RELEASE, timestamp }
		);
	}
}

void Joystick::Button::onPress(size_t timestamp)
{
	state = ButtonState::Pressed;
	for (auto& callback : onPressCallbacks) {
		manager->enqueueButtonEvent(
			JoystickManager::ButtonEvent{ callback, buttonNum, EVENT_TYPE_PRESS, timestamp }
		);
	}	
	for (auto& callback : onPressRepeatCallbacks) {
		callback.lastInvokationTime = timestamp;
		manager->enqueueButtonEvent(
			JoystickManager::ButtonEvent{callback.callback, buttonNum, EVENT_TYPE_PRESS, timestamp}
		);
	}
}

void Joystick::Button::onPressRepeatTimer(size_t timestamp)
{
	if (state == ButtonState::Pressed && !onPressRepeatCallbacks.empty()) 
		onPressRepeat(timestamp);
}

void Joystick::Button::setStateUnknown()
{
	state = ButtonState::Unknown;
}
