#include "McduWatcher.h"
#include "Copilot.h"
#include <algorithm>

bool isNumber(const std::string& str) 
{
	return std::all_of(str.begin(), str.end(), isdigit);
}

std::optional<double> toNumber(const std::string& str)
{
	if (isNumber(str))
		return stod(str);
	return {};
}

McduWatcher::McduWatcher(int pmSide, int port)
	:pmSide(pmSide)
{
	cptMcdu = std::make_shared<MCDU>(1, 1000, port);
	foMcdu = std::make_shared<MCDU>(2, 1000, port);
	if (pmSide == 1) {
		pmMcdu = cptMcdu;
		pfMcdu = foMcdu;
	} else if (pmSide == 2) {
		pmMcdu = foMcdu;
		pfMcdu = cptMcdu;
	}
}

void McduWatcher::update(std::function<void(const std::string&, const std::string&, int)> callback)
{

	auto rawPfDisp = pfMcdu->getRaw();
	if (rawPfDisp == "") {
		copilot::logger->warn("PF MCDU Http request error {}", pfMcdu->lastError());
		return;
	}

	std::lock_guard<std::recursive_mutex> lock(mainVarStore.mtx);

	auto& vars = mainVarStore.vars;

	auto pfDisp = pfMcdu->getStringFromRaw(rawPfDisp);
	{
		
		if (pfDisp.substr(9, 8) == "TAKE OFF" || pfDisp.substr(4, 12) == "TAKE OFF RWY") {
			vars["V1"] = toNumber(pfDisp.substr(48, 3));
			vars["Vr"] = toNumber(pfDisp.substr(96, 3));
			vars["V2"] = toNumber(pfDisp.substr(144, 3));
			vars["Vs"] = toNumber(pfDisp.substr(105, 3));
			vars["Vf"] = toNumber(pfDisp.substr(57, 3));
			vars["takeoffFlaps"] = toNumber(pfDisp.substr(161, 1));
			vars["takeoffRwy"] = pfDisp.substr(17, 3);
			if (vars["V1"] && vars["V2"] && vars["Vr"])
				isFmgcSetup.takeoff = true;
		} else if (pfDisp.substr(39, 7) == "FROM/TO") {
			vars["flyingCircuits"] = isalpha(pfDisp[63]) && pfDisp.substr(63, 4) == pfDisp.substr(68, 4);
		} else if (!isFmgcSetup.initB && pfDisp.substr(39, 9) == "ZFW/ZFWCG") {
			bool zfwEntered = isdigit(pfDisp[62]) || isdigit(pfDisp[63]);
			bool fuelEntered = isdigit(pfDisp[151]);
			isFmgcSetup.initB = zfwEntered && fuelEntered;
		}
		vars["isFmgcSetup"] = isFmgcSetup.takeoff && isFmgcSetup.initB;
	}
	
	if (callback) {
		auto rawPmDisp = pmMcdu->getRaw();
		if (rawPmDisp == "") {
			copilot::logger->warn("PM MCDU Http request error {}", pfMcdu->lastError());
			return;
		}
		callback(rawPfDisp, rawPmDisp, pmSide);
	}
}

std::optional<McduWatcher::LuaVar> McduWatcher::getVar(const std::string& name)
{
	return mainVarStore.getVar(name);
}

void McduWatcher::setVar(const std::string& name, LuaVar value)
{
	mainVarStore.setVar(name, value);
}

void McduWatcher::clearVar(const std::string& name)
{
	if (name == "isFmgcSetup") {
		isFmgcSetup.initB = false;
		isFmgcSetup.takeoff = false;
	}
	mainVarStore.clearVar(name);
}

std::optional<McduWatcher::LuaVar> McduWatcher::VariableStore::getVar(const std::string& name)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	if (vars.find(name) != vars.end())
		return vars[name];
	return {};
}

void McduWatcher::VariableStore::setVar(const std::string& name, LuaVar value)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	vars[name] = value;
}

void McduWatcher::VariableStore::clearVar(const std::string& name)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	vars.erase(name);
	return;
}
