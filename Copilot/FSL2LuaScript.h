#pragma once
#include "LuaPlugin.h"
#include "Joystick.h"
#include "Button.h"

class FSL2LuaScript : public LuaPlugin {
	void updateScript();
	virtual void initLuaState(sol::state_view lua) override;
public:
	using LuaPlugin::LuaPlugin;
	virtual void run() override;
	virtual void stopThread() override;
};