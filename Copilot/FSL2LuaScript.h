#pragma once
#include "LuaPlugin.h"

class FSL2LuaScript : public LuaPlugin {

public:

	using LuaPlugin::LuaPlugin;

	virtual bool run() override
	{
		if (!LuaPlugin::run()) return false;

		auto res = lua.safe_script(R"(Joystick.read())", sol::script_pass_on_error);
		if (!res.valid())
			onError(res);

		return res.valid();
	}
};