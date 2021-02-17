#include "Button.h"

Joystick::Button::Button(int buttonNum, int dataIndex)
	:buttonNum(buttonNum), dataIndex(dataIndex)
{
}

bool Joystick::Button::maybePress(size_t timestamp)
{
	if (state == ButtonState::Released) {
		onPress(timestamp);
		return !onPressRepeatCallbacks.empty();
	}
	return false;
}

void Joystick::Button::maybeRelease(size_t timestamp)
{
	if (state == ButtonState::Pressed)
		onRelease(timestamp);
}

void Joystick::Button::onPressRepeat(size_t timestamp)
{
	for (auto& callback : onPressRepeatCallbacks) {
		if (timestamp - callback.lastInvokationTime > static_cast<size_t>(callback.repeatInterval) - 2) {
			callback.lastInvokationTime = timestamp;
			callback.callback(buttonNum, 2, timestamp);
		}
	}
}

void Joystick::Button::onRelease(size_t timestamp)
{
	state = ButtonState::Released;
	for (auto& callback : onReleasecallbacks) 
		callback(buttonNum, 0, timestamp);
}

void Joystick::Button::onPress(size_t timestamp)
{
	state = ButtonState::Pressed;
	for (auto& callback : onPressCallbacks)
		callback(buttonNum, 1, timestamp);
	for (auto& callback : onPressRepeatCallbacks) {
		callback.lastInvokationTime = timestamp;
		callback.callback(buttonNum, 2, timestamp);
	}
}

void Joystick::Button::onPressRepeatTimer(size_t timestamp)
{
	if (state == ButtonState::Pressed && !onPressRepeatCallbacks.empty()) 
		onPressRepeat(timestamp);
}