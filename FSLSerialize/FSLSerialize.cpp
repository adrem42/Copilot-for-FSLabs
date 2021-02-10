#pragma warning(disable:4996)
#include <windows.h>
#include <SimConnect.h>
#include <iostream>
#include <thread>
#include <initpdk.h>
#include <Pdk.h>
#include <gauges.h>
#include <mutex>
#include <chrono>
#include <atomic>
#include "lua.hpp"
#include <spdlog/spdlog.h>

auto startTime = std::chrono::high_resolution_clock::now();
std::thread myThread;

std::shared_ptr<spdlog::logger> logger;
std::shared_ptr<spdlog::sinks::wincolor_stdout_sink_mt> consoleSink;

using namespace P3D;

IPdk* pdk;

HANDLE hSimConnect;
HANDLE hLuaThread;
std::mutex simMtx, luaMtx;
std::atomic_bool closeThread, resultsSaved, saveMenuItemVisible;
lua_State* L;

GAUGESIMPORT ImportTable = {
{ 0x0000000F, (PPANELS)NULL },
{ 0x00000000, NULL }
};
PPANELS Panels = NULL;

enum EVENT_ID {
	EVENT_MENU,
	EVENT_MENU_START,
	EVENT_MENU_STOP,
	EVENT_MENU_SAVE,
	EVENT_MENU_RECORD,
	EVENT_MENU_SHOW_MACROS
};

struct MACRO {
	int rectangle;
	int param;
};
std::shared_ptr<MACRO> currMacro = nullptr;

void attachLogToConsole()
{
	auto& sinks = logger->sinks();
	auto it = std::find(sinks.begin(), sinks.end(), consoleSink);
	if (it != sinks.end())
		sinks.erase(it);
	consoleSink = std::make_shared<spdlog::sinks::wincolor_stdout_sink_mt>();
	consoleSink->set_pattern("[%T] %^[%n]%$ %v");
	logger->sinks().push_back(consoleSink);
}

class MouseRectListenerCallback : public IMouseRectListenerCallback {
	DEFAULT_REFCOUNT_INLINE_IMPL()
		DEFAULT_IUNKNOWN_QI_INLINE_IMPL(MouseRectListenerCallback, IID_IUnknown)

public:

	enum class Mode { Record, Show } mode;
	MouseRectListenerCallback() :
		m_RefCount(1)
	{
	}
	virtual void MouseRectListenerProc(UINT id, MOUSE_CLICK_TYPE clickType) override
	{
		if (clickType == MOUSE_CLICK_RIGHT_RELEASE ||
			clickType == MOUSE_CLICK_LEFT_RELEASE ||
			clickType == MOUSE_CLICK_LEFT_SINGLE ||
			clickType == MOUSE_CLICK_RIGHT_SINGLE ||
			clickType == MOUSE_CLICK_WHEEL_DOWN ||
			clickType == MOUSE_CLICK_WHEEL_UP) {

			switch (mode) {

				case Mode::Record: 
				{
					std::lock_guard<std::mutex> lock(simMtx);
					MACRO macro{ id, (int)clickType };
					currMacro = std::make_shared<MACRO>(macro);
				}
				break;

				case Mode::Show:
				{
					logger->info("-----------------------------------");
					logger->info("ID: 0x{:X}, ClickType: {}", id, clickType);
				}
				break;
			}
		}
	}
} *mouseRectListenerCallback;

int getLvar(lua_State* L)
{
	PCSTRINGZ lvname = lua_tostring(L, 1);
	if (lvname == 0) return 0;
	if (strlen(lvname) == 0) return 0;
	ID i = check_named_variable(lvname);
	lua_pushnumber(L, get_named_variable_value(i));
	return 1;
}

int elapsedTime(lua_State* L)
{
	lua_pushnumber(L, std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::high_resolution_clock::now() - startTime).count());
	return 1;
}

void displayText(const char* msg)
{
	char buff[1024];
	strcpy(buff, msg);
	SimConnect_Text(hSimConnect, SIMCONNECT_TEXT_TYPE_MESSAGE_WINDOW, 0, 0, sizeof(buff), (void*)buff);
}

int displayTextFromLua(lua_State* L)
{
	displayText(lua_tostring(L, 1));
	return 0;
}

void checkLuaResult(lua_State* L, int result)
{
	if (result != 0)
		logger->error(lua_tostring(L, 1));
}

int luaWarn(lua_State* L)
{
	logger->warn(lua_tostring(L, 1));
	return 0;
}

int luaInfo(lua_State* L)
{
	logger->info(lua_tostring(L, 1));
	return 0;
}

void luaThread()
{
	attachLogToConsole();
	char lpFilename[MAX_PATH];
	HMODULE hMod = GetModuleHandleA("FSLSerialize");
	GetModuleFileNameA(hMod, lpFilename, MAX_PATH);
	std::string modulePath = lpFilename;
	std::string currentDir = modulePath.substr(0, modulePath.find("FSLSerialize.dll"));

	L = luaL_newstate();

	luaL_openlibs(L);

	lua_pushstring(L, currentDir.c_str());
	lua_setglobal(L, "currentDir");
	lua_pushcfunction(L, displayTextFromLua);
	lua_setglobal(L, "displayText");
	lua_pushcfunction(L, getLvar);
	lua_setglobal(L, "getLvar");
	lua_pushcfunction(L, elapsedTime);
	lua_setglobal(L, "getElapsedTime");
	lua_pushcfunction(L, luaWarn);
	lua_setglobal(L, "warn");
	lua_pushcfunction(L, luaInfo);
	lua_setglobal(L, "info");

	checkLuaResult(L, luaL_dofile(L, (currentDir + "FSLSerialize.lua").c_str()));

	while (!closeThread) {
		std::unique_lock<std::mutex> lock(simMtx);
		if (currMacro) {
			int rect = currMacro->rectangle;
			int param = currMacro->param;
			currMacro.reset();
			lock.unlock();

			std::lock_guard<std::mutex> lock(luaMtx);
			lua_getglobal(L, "onMacroDetected");
			lua_pushnumber(L, rect);
			lua_pushnumber(L, param);
			checkLuaResult(L, lua_pcall(L, 2, 0, 0));
		}
	}

	std::lock_guard<std::mutex> lock(luaMtx);
	lua_close(L);
	L = nullptr;
}

void restartLuaThread()
{
	if (myThread.joinable()) {
		closeThread = true;
		myThread.join();
		closeThread = false;
	}
	myThread = std::thread(luaThread);
}

void setSaveMenuItemVisible(bool visible)
{
	if (visible && !saveMenuItemVisible) {
		HRESULT hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_MENU, "Save the work", EVENT_MENU_SAVE, 0);
		saveMenuItemVisible = true;
		return;
	} else if (!visible && saveMenuItemVisible) {
		HRESULT hr = SimConnect_MenuDeleteSubItem(hSimConnect, EVENT_MENU, EVENT_MENU_SAVE);
		saveMenuItemVisible = false;
	}
}

void setupRecordingMenu()
{
	std::lock_guard<std::mutex> simLock(simMtx);
	std::lock_guard<std::mutex> luaLock(luaMtx);
	mouseRectListenerCallback->mode = MouseRectListenerCallback::Mode::Record;

	HRESULT hr;
	hr = SimConnect_MenuDeleteSubItem(hSimConnect, EVENT_MENU, EVENT_MENU_RECORD);
	if (L != nullptr) setSaveMenuItemVisible(true);
	hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_MENU, "Start lua", EVENT_MENU_START, 0);
	hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_MENU, "Stop lua", EVENT_MENU_STOP, 0);
	hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_MENU, "Show macros", EVENT_MENU_SHOW_MACROS, 0);
}

void setupMacroDisplayMenu()
{
	std::lock_guard<std::mutex> simLock(simMtx);
	std::lock_guard<std::mutex> luaLock(luaMtx);
	mouseRectListenerCallback->mode = MouseRectListenerCallback::Mode::Show;

	HRESULT hr;
	hr = SimConnect_MenuDeleteSubItem(hSimConnect, EVENT_MENU, EVENT_MENU_STOP);
	hr = SimConnect_MenuDeleteSubItem(hSimConnect, EVENT_MENU, EVENT_MENU_START);
	setSaveMenuItemVisible(false);
	hr = SimConnect_MenuDeleteSubItem(hSimConnect, EVENT_MENU, EVENT_MENU_SHOW_MACROS);
	hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_MENU, "Record macros", EVENT_MENU_RECORD, 0);
}

void CALLBACK MyDispatchProcDLL(SIMCONNECT_RECV* pData, DWORD cbData, void* pContext)
{
	switch (pData->dwID) 
	{
		case SIMCONNECT_RECV_ID_EVENT: 
		{
			SIMCONNECT_RECV_EVENT* evt = (SIMCONNECT_RECV_EVENT*)pData;
			switch (evt->uEventID) 
			{

				case EVENT_MENU_START:
				{
					restartLuaThread();
					setSaveMenuItemVisible(true);
					break;
				}

				case EVENT_MENU_SAVE:
				{
					if (L != nullptr) {
						std::lock_guard<std::mutex> lock(luaMtx);
						lua_getglobal(L, "saveResults");
						checkLuaResult(L, lua_pcall(L, 0, 0, 0));
					}
					
					break;
				}

				case EVENT_MENU_STOP:
				{
					if (myThread.joinable()) {
						setSaveMenuItemVisible(false);
						closeThread = true;
						myThread.join();
						closeThread = false;
					}
					break;
				}

				case EVENT_MENU_SHOW_MACROS:
				{
					setupMacroDisplayMenu();
					break;
				}

				case EVENT_MENU_RECORD:
				{
					setupRecordingMenu();
					break;
				}

			}
		}
	}
}

void DLLStart(__in __notnull IPdk* pPdk)
{

	logger = std::make_shared<spdlog::logger>("FSLSerialize");
	logger->flush_on(spdlog::level::trace);

	attachLogToConsole();

	if (Panels != NULL) {
		ImportTable.PANELSentry.fnptr = (PPANELS)Panels;
	}
	if (pPdk != nullptr) PdkServices::Init(pPdk);
	pdk = pPdk;

	mouseRectListenerCallback = new MouseRectListenerCallback();
	mouseRectListenerCallback->mode = MouseRectListenerCallback::Mode::Record;
	PdkServices::GetWindowPluginSystem()->RegisterMouseRectListenerCallback(mouseRectListenerCallback);

	if (SUCCEEDED(SimConnect_Open(&hSimConnect, "FSLSerialize", NULL, 0, NULL, 0))) {

		HRESULT hr;
		hr = SimConnect_MenuAddItem(hSimConnect, "FSLSerialize", EVENT_MENU, 0);
		setupRecordingMenu();
		hr = SimConnect_CallDispatch(hSimConnect, MyDispatchProcDLL, NULL);
	}

}

void __stdcall DLLStop(void)
{
	PdkServices::Shutdown();
	if (hSimConnect) SimConnect_Close(hSimConnect);
}