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

extern "C"
{
#include "../lua515/include/lua.h"
#include "../lua515/include/lauxlib.h"
#include "../lua515/include/lualib.h"
}

auto startTime = std::chrono::high_resolution_clock::now();
std::thread* myThread;

using namespace P3D;

HANDLE hSimConnect;
HANDLE hLuaThread;
std::mutex simMtx, luaMtx;
std::atomic<bool> closeThread = false;
lua_State* L;

GAUGESIMPORT ImportTable = {
{ 0x0000000F, (PPANELS)NULL },
{ 0x00000000, NULL }
};
PPANELS Panels = NULL;

struct MACRO {
	int rectangle;
	int param;
};
std::shared_ptr<MACRO> currMacro = nullptr;

class MouseRectListenerCallback : public IMouseRectListenerCallback {
	DEFAULT_REFCOUNT_INLINE_IMPL()
		DEFAULT_IUNKNOWN_QI_INLINE_IMPL(MouseRectListenerCallback, IID_IUnknown)

public:
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
			//std::cout << "--------------------" << std::endl;
			//std::cout << std::hex << id << std::endl << std::dec << clickType << std::endl;

			std::lock_guard<std::mutex> lock(simMtx);
			MACRO macro{ id, (int)clickType };
			currMacro = std::make_shared<MACRO>(macro);
		}
	}
};

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

void luaThread()
{

	L = luaL_newstate();

	luaL_openlibs(L);

	std::string slnDir = "C:\\Users\\Peter\\source\\repos\\FSLabs Copilot\\";

	lua_pushstring(L, slnDir.c_str());
	lua_setglobal(L, "SLNDIR");

	lua_pushcfunction(L, getLvar);
	lua_setglobal(L, "getLvar");
	lua_pushcfunction(L, elapsedTime);
	lua_setglobal(L, "getElapsedTime");

	luaL_dofile(L, (slnDir + "FSLSerialize\\FSLSerialize.lua").c_str());

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
			lua_pcall(L, 2, 0, 0);
		}
	}

	lua_close(L);

}

void restartLuaThread()
{
	if (myThread != nullptr) {
		closeThread = true;
		myThread->join();
		delete myThread;
		closeThread = false;
	}
	myThread = new std::thread(luaThread);
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
				case 0:
					switch (evt->dwData) 
					{
						case 0: 
						{
							std::lock_guard<std::mutex> lock(luaMtx);
							restartLuaThread();
							break;
						}
						case 1: 
						{
							std::lock_guard<std::mutex> lock(luaMtx);
							lua_getglobal(L, "saveResults");
							lua_pcall(L, 0, 0, 0);
							break;
						}
					}
			}
		}
	}
}

void DLLStart(__in __notnull IPdk* pPdk)
{

	if (pPdk != nullptr) {
		PdkServices::Init(pPdk);
		std::cout << "PDK initialized" << std::endl;
	} else {
		std::cout << "PDK not found" << std::endl;
	}

	PdkServices::GetWindowPluginSystem()->RegisterMouseRectListenerCallback(new MouseRectListenerCallback);

	if (Panels != NULL) {
		std::cout << "Panels are here" << std::endl;
		ImportTable.PANELSentry.fnptr = (PPANELS)Panels;
	}

	if (SUCCEEDED(SimConnect_Open(&hSimConnect, "FSLSerialize", NULL, 0, NULL, 0))) {

		HRESULT hr;
		hr = SimConnect_MapClientEventToSimEvent(hSimConnect, 0, "SMOKE_ON");
		hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, 0, 0);

		hr = SimConnect_SetNotificationGroupPriority(hSimConnect, 0, SIMCONNECT_GROUP_PRIORITY_HIGHEST);

		hr = SimConnect_CallDispatch(hSimConnect, MyDispatchProcDLL, NULL);

		std::cout << "Link to SimConnect established" << std::endl;
	}

}

void __stdcall DLLStop(void)
{
}