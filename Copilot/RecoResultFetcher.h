#pragma once
#include "../lua515/include/lua.hpp"
#include <chrono>
#include <atomic>
#include <vector>
#include <Windows.h>
#include "Recognizer.h"

class RecoResultFetcher : ISpNotifyCallback {
	Recognizer* m_recognizer;
	std::vector<RuleID> m_recoResults;
	bool m_muted = false;
	std::atomic_bool m_luaNotified;
	std::chrono::milliseconds m_delayBeforeUnmute = std::chrono::milliseconds(1000);
	std::mutex m_mutex;
	std::chrono::time_point<std::chrono::system_clock> m_muteKeyReleasedTime = std::chrono::system_clock::now();
	void notifyLua();
	void fetchResults();
	HRESULT NotifyCallback(WPARAM wParam, LPARAM lParam) override;
public:
	RecoResultFetcher(Recognizer* recognizer);
	bool registerCallback();
	void onMuteKeyEvent(bool isMuteKeyPressed);
	sol::as_table_t<std::vector<RuleID>> getResults();
};