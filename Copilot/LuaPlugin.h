#pragma once
#include <sol/sol.hpp>
#include <thread>
#include "KeyBindManager.h"
#include "JoystickManager.h"

class LuaPlugin {

protected:

	std::chrono::time_point<std::chrono::high_resolution_clock> startTime = std::chrono::high_resolution_clock::now();

	std::shared_ptr<KeyBindManager> keyBindManager = nullptr;
	std::shared_ptr<JoystickManager> joystickManager = nullptr;

	std::thread thread;
	sol::state lua;

	std::string path;

	virtual void initLuaState(sol::state_view lua);

	void onError(const sol::error&);

	virtual void run();

public:

	LuaPlugin(const std::string&);

	virtual void stopThread();

	void launchThread();

	~LuaPlugin();
};

