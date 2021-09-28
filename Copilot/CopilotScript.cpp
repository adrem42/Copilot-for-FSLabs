

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

	std::optional<std::string> outputDevice = options["callouts"]["device"];
	bool volumeControl = options["callouts"]["ACP_volume_control"].get_or(1) == 1;
	if (!volumeControl)
		logger->info("ACP volume control is disabled");
	int pmSide = options["general"]["PM_seat"];
	double volume = options["callouts"]["volume"];

	auto copilotTts = lua["copilot"]["TextToSpeech"]["new"](outputDevice);

	lua["copilot"]["PLAY_BLOCKING"] = lua["copilot"]["TextToSpeech"]["PLAY_BLOCKING"];

	lua["copilot"]["speak"] = [&, copilotTts = copilotTts.get<sol::userdata>()](const std::wstring& phrase, std::optional<size_t> delay) {
		copilotTts["speak"](phrase, delay);
	};
	auto ptr = copilotTts.get<CComPtr<ISpVoice>>();
	Sound::init(outputDevice, pmSide, volume * 0.01, volumeControl, ptr);

	auto copilot = lua["copilot"];

	copilot["getOutputDeviceName"] = Sound::getDeviceName;

	copilot["onVolKnobPosChanged"] = Sound::onVolumeChanged;

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
		logger->info(str);
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

	auto SoundType = lua.new_usertype<Sound>("Sound",
											 sol::constructors<Sound(const std::string&, int, double),
											 Sound(const std::string&, int),
											 Sound(const std::string&)>());
	SoundType["play"] = sol::overload(static_cast<void (Sound::*)(int)>(&Sound::enqueue),
									  static_cast<void (Sound::*)()>(&Sound::enqueue));

	auto McduWatcherType = lua.new_usertype<McduWatcher>("McduWatcher");
	McduWatcherType["getVar"] = &McduWatcher::getVar;
	McduWatcherType["clearVar"] = &McduWatcher::clearVar;
	

	int port = options["general"]["http_port"];
	mcduWatcher = std::make_unique<McduWatcher>(pmSide, port);
	copilot["mcduWatcher"] = mcduWatcher;

}

void CopilotScript::onLuaStateInitialized()
{
	
}



void CopilotScript::onSimStart()
{	
}

void CopilotScript::onSimExit()
{
}

void CopilotScript::onBackgroundTimer()
{
	FSL2LuaScript::onBackgroundTimer();
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
}

CopilotScript::~CopilotScript()
{
	
	if (voice)
		voice->Release();
	CoUninitialize();
	stopBackgroundThread();
	stopThread();
}