
#pragma once
#include "LuaPlugin.h"
#include "Joystick.h"
#include "Button.h"
#include <Windows.h>
#include "Copilot.h"
#include <IUnknownHelper.h>
#include <Pdk.h>
#include "CallbackRunner.h"
#include "Recognizer.h"
#include "RecognizerCallback.h"

class FSL2LuaScript : public LuaPlugin {

protected:

	std::unique_ptr<CallbackRunner> callbackRunner = nullptr;

	class MouseRectListenerCallback : public P3D::IMouseRectListenerCallback {
		DEFAULT_REFCOUNT_INLINE_IMPL()
			DEFAULT_IUNKNOWN_QI_INLINE_IMPL(MouseRectListenerCallback, IID_IUnknown)
			const size_t scriptID;
	public:
		MouseRectListenerCallback(size_t scriptID) :scriptID(scriptID), m_RefCount(1) {}
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

	struct Events {
		HANDLE * events;
		size_t numEvents;
		size_t KEYBOARD_EVENT;
		size_t JOYSTICK_EVENT_MIN;
		size_t JOYSTICK_EVENT_MAX;
		size_t SHUTDOWN_EVENT;
		size_t EVENT_LUA_CALLBACK;
	};

	struct TtsEvent {
		ISpVoice* voice;
		size_t timestamp;
		std::wstring phrase;
	};

	std::vector<std::shared_ptr<RecognizerCallback>> recognizerCallbacks;

	std::mutex ttsQueueMutex;
	std::queue<TtsEvent> ttsQueue;

	std::atomic_bool backgroundThreadRunning = false;
	std::thread backgroundThread;
	virtual void onBackgroundTimer();
	void startBackgroundThread();
	void stopBackgroundThread();

	virtual void initLuaState(sol::state_view lua) override;

	virtual Events* createEvents();

	virtual void onEvent(Events* events, DWORD eventIdx);

public:

	void enqueueCallback(LuaCallback);
	using LuaPlugin::LuaPlugin;
	virtual void run() override;
	virtual void stopThread() override;

	virtual ~FSL2LuaScript();
};