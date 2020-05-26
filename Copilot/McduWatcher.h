#pragma once
#include <memory>
#include <variant>
#include <optional>
#include <mutex>
#include <map>
#include "../HttpRequest/HttpRequest.h"

using LuaVar = std::optional<std::variant<std::string, bool, int>>;

class McduWatcher {
	std::shared_ptr<Mcdu> cptMcdu;
	std::shared_ptr<Mcdu> foMcdu;
	std::shared_ptr<Mcdu> pmMcdu;
	std::shared_ptr<Mcdu> pfMcdu;
	std::map<std::string, LuaVar> vars;
	std::mutex mtx;
	struct {
		bool takeoff = false;
		bool initB = false;
	} isFmgcSetup;
public:
	McduWatcher(int pmSide, int port);
	void update();
	LuaVar getVar(const std::string& name);
	void resetVars();
};
