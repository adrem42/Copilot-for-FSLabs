#pragma once
#include <sol/sol.hpp>
#include <thread>

class LuaPlugin {

protected:

	std::thread thread;
	sol::state lua;

	std::string path;

	void initLuaState(sol::state_view lua);

	void onError(const sol::error&);

	virtual bool run();

public:

	LuaPlugin(const std::string&);

	void stopThread();

	void launchThread();
};

