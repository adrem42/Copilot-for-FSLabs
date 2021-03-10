#pragma once
#include <vector>
#include <chrono>
#include <functional>
#include "Joystick.h"
#include "JoystickManager.h"

class Joystick::Button {

	friend class Joystick;

	static const uint8_t EVENT_TYPE_PRESS = 0;
	static const uint8_t EVENT_TYPE_REPEATED_PRESS = 1;
	static const uint8_t EVENT_TYPE_RELEASE = 2;

	enum class ButtonState {
		Pressed, Released
	};

	const std::shared_ptr<JoystickManager> manager;

	static const int DEFAULT_REPEAT_INTERVAL = 80;

	ButtonState state = ButtonState::Released;

	void onPressRepeat(size_t timestamp);

	void onRelease(size_t timestamp);

	void onPress(size_t timestamp);

public:

	struct OnPressRepeatCallback {
		ButtonCallback callback;
		int repeatInterval = DEFAULT_REPEAT_INTERVAL;
		size_t lastInvokationTime = 0;
	};

	const uint16_t buttonNum;
	const uint16_t dataIndex;

	std::vector<Joystick::ButtonCallback> onPressCallbacks;
	std::vector<OnPressRepeatCallback> onPressRepeatCallbacks;
	std::vector<Joystick::ButtonCallback> onReleasecallbacks;

	Button(uint16_t buttonNum, uint16_t dataIndex, std::shared_ptr<JoystickManager>);

	bool maybePress(size_t);

	void maybeRelease(size_t);

	void onPressRepeatTimer(size_t);

};
