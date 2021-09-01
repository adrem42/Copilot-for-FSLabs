

#include "CopilotScript.h"
#include "Copilot.h"
#include "Sound.h"
#include "McduWatcher.h"
#include <functional>
#include <string>
#include <filesystem>
#include "SimInterface.h"
#include <sapi.h>
#include <sphelper.h>

void CopilotScript::initLuaState(sol::state_view lua)
{
	FSL2LuaScript::initLuaState(lua);
	stopBackgroundThread();

	std::string packagePath = lua["package"]["path"];

	
	lua.registry()["asyncCallbacks"] = lua.create_table();

	sol::protected_function_result res = lua.script(R"(require "copilot.LoadCopilotOptions")");

	if (!res.valid())
		throw ScriptStartupError(res);

	auto options = lua["copilot"]["UserOptions"];

	int devNum = options["callouts"]["device_id"];
	int pmSide = options["general"]["PM_seat"];
	double volume = options["callouts"]["volume"];

	if (SUCCEEDED(CoInitialize(NULL))) {
		HRESULT hr = CoCreateInstance(CLSID_SpVoice, NULL, CLSCTX_ALL, IID_ISpVoice, reinterpret_cast<void**>(&voice));
		int deviceId = options["callouts"]["sapi_device_id"];
		if (deviceId != -1) {
			CComPtr<IEnumSpObjectTokens> enumTokens;
			HRESULT hr = SpEnumTokens(SPCAT_AUDIOIN, NULL, NULL, &enumTokens);
			CComPtr<ISpObjectToken> objectToken;
			if (SUCCEEDED(hr))
				hr = enumTokens->Item(deviceId - 1, &objectToken);
			if (SUCCEEDED(hr))
				hr = SpCreateObjectFromToken(objectToken, &voice);
			if (FAILED(hr)) {
				throw ScriptStartupError("Error setting non-default output device");
			}
		}
	}

	Sound::init(devNum, pmSide, volume * 0.01, voice);

	auto copilot = lua["copilot"];

	copilot["onVolKnobPosChanged"] = Sound::onVolumeChanged;

	copilot["speak"] = [&](const std::wstring& phrase, std::optional<size_t> delay) {
		if (delay == -1) {
			voice->Speak(phrase.c_str(), 0, NULL);
		} else {
			std::lock_guard<std::mutex> lock(ttsQueueMutex);
			ttsQueue.push(std::make_pair(elapsedTime() + delay.value_or(0), phrase));
		}
	};

	mcduWatcherLua.open_libraries();
	mcduWatcherLua["print"] = [this](sol::variadic_args va) {
		std::string str;
		for (size_t i = 0; i < va.size(); i++) {
			auto v = va[i];
			str += this->lua["tostring"](v.get<sol::object>());
			if (i != va.size() - 1) {
				str += " ";
			}
		}
		copilot::logger->info(str);
	};

	mcduWatcherToArray = mcduWatcherLua.script(R"(
		local colors = {
			["1"] = "cyan",
			["2"] = "grey",
			["4"] = "green",
			["5"] = "magenta",
			["6"] = "amber",
			["7"] = "white",
		}
				
		return function(response)
			local display = {}
			for unitArray in response:gmatch("%[(.-)%]") do
				local unit = {}
				if unitArray:find(",") then
					local char, color, isBold = unitArray:match('(%d+),(%d),(%d)')
					unit.char = string.char(char)
					unit.color = colors[color] or tonumber(color)
					unit.isBold = tonumber(isBold) == 0
				end
				display[#display + 1] = unit
			end
			return display
		end
	)");

	mcduWatcherLua["getVar"] = [this](const std::string& key) {
		return currMcduWatcherVarStore->getVar(key);
	};
	mcduWatcherLua["setVar"] = [this](const std::string& key, McduWatcher::LuaVar value) {
		 currMcduWatcherVarStore->setVar(key, value);
	};
	mcduWatcherLua["clearVar"] = [this](const std::string& key) {
		currMcduWatcherVarStore->clearVar(key);
	};

	copilot["addMcduCallback"] = [this](const std::string& path) {
		if (backgroundThread.joinable())
			throw "You must call addMcduCallback during the initial setup";
		sol::protected_function_result pfr = mcduWatcherLua.safe_script_file(path);
		if (!pfr.valid()) {
			throw ScriptStartupError(pfr);
		}
		if (pfr.get_type() != sol::type::function) {
			throw ScriptStartupError(path + " needs to return a function");
		}
		McduWatcherLuaCallback& callback = mcduWatcherLuaCallbacks.emplace_back(McduWatcherLuaCallback {pfr.get<sol::protected_function>()});
		auto getVar = [varStore = callback.varStore] (const std::string& key) {
			return varStore->getVar(key);
		};
		auto clearVar = [varStore = callback.varStore](const std::string& key) {
			varStore->clearVar(key);
		};
		return std::make_tuple(std::move(getVar), std::move(clearVar));
	};

	auto RecoResultFetcherType = lua.new_usertype<RecoResultFetcher>("RecoResultFetcher");
	RecoResultFetcherType["getResults"] = &RecoResultFetcher::getResults;

	auto SoundType = lua.new_usertype<Sound>("Sound",
											 sol::constructors<Sound(const std::string&, int, double),
											 Sound(const std::string&, int),
											 Sound(const std::string&)>());
	SoundType["play"] = sol::overload(static_cast<void (Sound::*)(int)>(&Sound::enqueue),
									  static_cast<void (Sound::*)()>(&Sound::enqueue));

	auto McduWatcherType = lua.new_usertype<McduWatcher>("McduWatcher");
	McduWatcherType["getVar"] = &McduWatcher::getVar;
	McduWatcherType["clearVar"] = &McduWatcher::clearVar;
	
	bool voiceControl = options["voice_control"]["enable"] == 1;
	if (voiceControl) {
		try {
			int deviceId = options["voice_control"]["device_id"];
			if (deviceId != Recognizer::DEFAULT_DEVICE_ID)
				deviceId--;
			recognizer = std::make_shared<Recognizer>(deviceId);
		} 		catch (std::exception& ex) {
			throw ScriptStartupError("Failed to create recognizer: " + std::string(ex.what()));
		}
		
		recoResultFetcher = std::make_shared<RecoResultFetcher>(recognizer);
	}

	int port = options["general"]["http_port"];
	mcduWatcher = std::make_unique<McduWatcher>(pmSide, port);
	recognizer->makeLuaBindings(lua);
	copilot["recognizer"] = recognizer;
	copilot["recoResultFetcher"] = recoResultFetcher;
	copilot["mcduWatcher"] = mcduWatcher;

}

void CopilotScript::onLuaStateInitialized()
{
	startBackgroundThread();
}

FSL2LuaScript::Events* CopilotScript::createEvents()
{
	auto parentEvents = FSL2LuaScript::createEvents();

	size_t numEvents = parentEvents->numEvents + 1;

	HANDLE* events = new HANDLE[numEvents]();

	for (size_t i = 0; i < parentEvents->numEvents; ++i) {
		events[i] = parentEvents->events[i];
	}

	auto e = new Events{*parentEvents };

	e->EVENT_RECO_EVENT = numEvents - 1;
	e->events = events;
	e->numEvents = numEvents;

	events[e->EVENT_RECO_EVENT] = recoResultFetcher ? recoResultFetcher->event() : CreateEvent(0, 0, 0, 0);
	delete[] parentEvents->events;
	delete parentEvents;
	return e;
}

void CopilotScript::onEvent(FSL2LuaScript::Events* _events, DWORD eventIdx)
{
	Events* events = reinterpret_cast<Events*>(_events);
	if (eventIdx == events->EVENT_RECO_EVENT) {
		sol::protected_function trigger = lua["Event"]["trigger"];
		sol::table voiceCommands = lua["Event"]["voiceCommands"];
		for (auto& result : recoResultFetcher->getResults()) {
			sol::table voiceCommand = voiceCommands[result.ruleID];
			callProtectedFunction(trigger, voiceCommand, std::move(result));
		}
	} else {
		FSL2LuaScript::onEvent(_events, eventIdx);
	}
}

void CopilotScript::onSimStart()
{
	startBackgroundThreadTimer();
}

void CopilotScript::onSimExit()
{
	stopBackgroundThreadTimer();
}

void CopilotScript::onMessageLoopTimer()
{
	if (copilot::isFslAircraft) {
		if (mcduWatcherLuaCallbacks.size()) {
			mcduWatcher->update([this](const std::string& pf, const std::string& pm, int pmSide) {
				sol::table data = mcduWatcherLua.create_table();
				sol::table pfDisplay = mcduWatcherToArray(pf);
				sol::table pmDisplay = mcduWatcherToArray(pm);
				pfDisplay["str"] = MCDU::getStringFromRaw(pf);
				pmDisplay["str"] = MCDU::getStringFromRaw(pm);
				data["PM"] = pmDisplay;
				data["PF"] = pfDisplay;
				if (pmSide == 1) {
					data["pmSide"] = "CPT";
					data["CPT"] = pmDisplay;
					data["FO"] = pfDisplay;
				} else {
					data["pmSide"] = "FO";
					data["CPT"] = pfDisplay;
					data["FO"] = pmDisplay;
				}
				for (auto& callback : mcduWatcherLuaCallbacks) {
					currMcduWatcherVarStore = callback.varStore.get();
					callProtectedFunction(callback.callback, data);
				}
			});
		} else {
			mcduWatcher->update(nullptr);
		}
	}
	Sound::update(copilot::isFslAircraft);
	std::lock_guard<std::mutex> lock(ttsQueueMutex);
	if (ttsQueue.size() && elapsedTime() >= ttsQueue.front().first) {
		HRESULT hr = voice->Speak(ttsQueue.front().second.c_str(), SPF_ASYNC, NULL);
		ttsQueue.pop();
	}
}

void CopilotScript::actuallyStartBackgroundThreadTimer()
{
	backgroundThreadTimerId = SetTimer(NULL, backgroundThreadTimerId, 70, NULL);
}

void CopilotScript::actuallyStopBackgroundThreadTimer()
{
	KillTimer(NULL, backgroundThreadTimerId);
}

void CopilotScript::runMessageLoop()
{
	if (recoResultFetcher) {
		try {
			recoResultFetcher->registerCallback();
		} 		catch (std::exception& ex) {
			stopThread();
			copilot::logger->error("Failed to register SAPI callback. Copilot will stop execution.");
			return;
		}
	}
	actuallyStartBackgroundThreadTimer();
	MSG msg = {};
	while (GetMessage(&msg, NULL, 0, 0)) {
		switch (msg.message) {
			case (WM_STARTTIMER):
				actuallyStartBackgroundThreadTimer();
				break;
			case (WM_STOPTIMER):
				actuallyStopBackgroundThreadTimer();
				break;
			case WM_TIMER:
				onMessageLoopTimer();
				break;
		}
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}
	actuallyStopBackgroundThreadTimer();
}

void CopilotScript::startBackgroundThread()
{
	backgroundThread = std::thread(&CopilotScript::runMessageLoop, this);
}

void CopilotScript::stopBackgroundThread()
{
	if (backgroundThread.joinable()) {
		PostThreadMessage(GetThreadId(backgroundThread.native_handle()),
						  WM_QUIT, 0, 0);
		backgroundThread.join();
	}
}

void CopilotScript::startBackgroundThreadTimer()
{
	if (backgroundThread.joinable()) {
		PostThreadMessage(GetThreadId(backgroundThread.native_handle()),
						  WM_STARTTIMER, 0, 0);
	}
}

void CopilotScript::stopBackgroundThreadTimer()
{
	if (backgroundThread.joinable()) {
		PostThreadMessage(GetThreadId(backgroundThread.native_handle()),
						  WM_STOPTIMER, 0, 0);
	}
}

CopilotScript::~CopilotScript()
{
	
	if (voice)
		voice->Release();
	CoUninitialize();
	stopBackgroundThread();
	stopThread();
}