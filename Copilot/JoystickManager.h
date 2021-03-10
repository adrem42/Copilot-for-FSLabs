#pragma once
#include <vector>
#include <memory>
#include <Windows.h>
#include <queue>
#include <mutex>
#include "Joystick.h"

class JoystickManager {
	
	friend class Joystick;
	friend class Joystick::Button;

	std::vector<std::shared_ptr<Joystick>> joysticks;
	std::mutex eventMutex;

	struct ButtonEvent {
		Joystick::ButtonCallback callback;
		uint16_t buttonNum;
		uint16_t action;
		size_t timestamp;
	};

	struct AxisEvent {
		Joystick::AxisCallback::CallbackType callback;
		double value;
	};

	std::queue<ButtonEvent> buttonEvents;

	std::queue<AxisEvent> axisEvents;

	HANDLE newButtonEventsNotification = CreateEvent(0, 0, 0, 0);
	HANDLE newAxisEventsNotification = CreateEvent(0, 0, 0, 0);

public:

	friend class Joystick;

	std::vector<HANDLE> getEvents();

	void onNewDataAvailable(size_t eventIdx);

	void enqueueButtonEvent(ButtonEvent&&);
	void enqueueAxisEvent(AxisEvent&&);

	void dispatchEvents();
	bool hasEvents();

};

