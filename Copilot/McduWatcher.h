#pragma once
#include <memory>
#include <variant>
#include <optional>
#include <mutex>
#include <map>
#include "MCDU.h"
#include <sol/sol.hpp>


class McduWatcher {
public:
	using LuaVar = std::variant<std::string, bool, double>;
	struct VariableStore {
		std::recursive_mutex mtx;
		std::unordered_map<std::string, std::optional<LuaVar>> vars;
		std::optional<LuaVar> getVar(const std::string& name);
		void setVar(const std::string& name, LuaVar var);
		void clearVar(const std::string& name);
	};
private:
	std::shared_ptr<MCDU> cptMcdu;
	std::shared_ptr<MCDU> foMcdu;
	std::shared_ptr<MCDU> pmMcdu;
	std::shared_ptr<MCDU> pfMcdu;
	VariableStore mainVarStore;
	int pmSide;
	struct {
		bool takeoff = false;
		bool initB = false;
	} isFmgcSetup;
public:
	std::optional<LuaVar> getVar(const std::string& name);
	void setVar(const std::string& name, LuaVar var);
	void clearVar(const std::string& name);
	McduWatcher(int pmSide, int port);
	void update(std::function<void(const std::string&, const std::string&, int)>);
};
