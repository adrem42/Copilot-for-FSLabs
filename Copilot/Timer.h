#pragma once
#include <chrono>
#include "Copilot.h"
class Timer {

	using TimePoint = std::chrono::time_point<std::chrono::system_clock>;
	TimePoint start = std::chrono::system_clock::now();
	std::string prefix;

public:
	Timer(const std::string& prefix)
		:prefix(prefix)
	{
	}
	~Timer()
	{
		auto now = std::chrono::system_clock::now();
		double duration = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
		copilot::logger->trace("{} took {} ms", prefix, duration);
	}
};

