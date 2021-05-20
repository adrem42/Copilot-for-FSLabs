
#pragma once
#include "LuaPlugin.h"
#include "Joystick.h"
#include "Button.h"
#include <Windows.h>
#include "Copilot.h"
#include <IUnknownHelper.h>
#include <Pdk.h>
#include "CallbackRunner.h"

class FSL2LuaScript : public LuaPlugin {

protected:

	std::unique_ptr<CallbackRunner> callbackRunner = nullptr;

	class MouseRectListenerCallback : public P3D::IMouseRectListenerCallback {
		DEFAULT_REFCOUNT_INLINE_IMPL()
			DEFAULT_IUNKNOWN_QI_INLINE_IMPL(MouseRectListenerCallback, IID_IUnknown)
			FSL2LuaScript* pScript;
	public:
		MouseRectListenerCallback(FSL2LuaScript* pScript) :pScript(pScript), m_RefCount(1) {}
		virtual void MouseRectListenerProc(UINT, P3D::MOUSE_CLICK_TYPE) override;
	};

	friend class LuaTextMenu;
	friend class LuaNamedSimConnectEvent;

	std::unique_ptr<MouseRectListenerCallback> mouseMacroCallback = nullptr;
	sol::table mouseMacroEvent;

	std::shared_ptr<KeyBindManager> keyBindManager = nullptr;
	std::shared_ptr<JoystickManager> joystickManager = nullptr;

	using LuaCallback = std::function<void(sol::state_view&)>;
	std::mutex luaCallbackQueueMutex;
	std::queue<LuaCallback> luaCallbacks;
	HANDLE luaCallbackEvent = CreateEvent(0, 0, 0, 0);
	void enqueueCallback(LuaCallback);

	struct Events {
		HANDLE * events;
		size_t numEvents;
		size_t KEYBOARD_EVENT;
		size_t JOYSTICK_EVENT_MIN;
		size_t JOYSTICK_EVENT_MAX;
		size_t SHUTDOWN_EVENT;
		size_t EVENT_LUA_CALLBACK;
	};

	virtual void initLuaState(sol::state_view lua) override;

	virtual Events* createEvents();

	virtual void onEvent(Events* events, DWORD eventIdx);

public:

	using LuaPlugin::LuaPlugin;
	virtual void run() override;
	virtual void stopThread() override;

	virtual ~FSL2LuaScript();
};