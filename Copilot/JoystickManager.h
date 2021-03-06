#pragma once
#include <vector>
#include <memory>
#include <Windows.h>

class Joystick;

class JoystickManager {

	std::vector<std::shared_ptr<Joystick>> joysticks;

public:

	friend class Joystick;

	std::vector<HANDLE> getEvents();

	void onEvent(size_t eventIdx);

};

