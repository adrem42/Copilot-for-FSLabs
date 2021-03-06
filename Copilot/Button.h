#pragma once
#include <vector>
#include <chrono>
#include <functional>
#include "Joystick.h"

class Joystick::Button {

	friend class Joystick;

	enum class ButtonState {
		Pressed, Released
	};

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

	const int buttonNum;
	const int dataIndex;

	std::vector<Joystick::ButtonCallback> onPressCallbacks;
	std::vector<OnPressRepeatCallback> onPressRepeatCallbacks;
	std::vector<Joystick::ButtonCallback> onReleasecallbacks;

	Button(int buttonNum, int dataIndex);

	bool maybePress(size_t);

	void maybeRelease(size_t);

	void onPressRepeatTimer(size_t);

};
