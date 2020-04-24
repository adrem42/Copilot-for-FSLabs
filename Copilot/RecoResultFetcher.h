#pragma once
extern "C"
{
#include "../lua515/include/lua.h"
#include "../lua515/include/lauxlib.h"
#include "../lua515/include/lualib.h"
}

#include <chrono>
#include <atomic>
#include <queue>
#include "Recognizer.h"

using TimePoint = std::chrono::time_point<std::chrono::system_clock>;

class RecoResultFetcher {
	std::shared_ptr<Recognizer> recognizer;
	bool muted = false;
	std::chrono::milliseconds delayBeforeUnmute = std::chrono::milliseconds(1000);
	std::mutex mtx;
	TimePoint muteKeyRelasedTime = std::chrono::system_clock::now();
public:
	void onMuteKeyEvent(bool isMuteKeyPressed);
	std::queue<DWORD> recoResults;
	RecoResultFetcher(std::shared_ptr<Recognizer> recognizer);
	void fetchResults();
	std::optional<DWORD> getResult();
};
