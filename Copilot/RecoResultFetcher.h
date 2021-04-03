#pragma once
#include <lua.hpp>
#include <chrono>
#include <atomic>
#include <vector>
#include <Windows.h>
#include "Recognizer.h"
#include "functional"

class RecoResultFetcher : ISpNotifyCallback {
public:
	using UserNotifyCallback = std::function<void()>;
private:
	const std::shared_ptr<Recognizer> recognizer;
	std::vector<RecoResult> recoResults;
	bool muted = false, muteKeyDepressed = false;
	std::atomic_bool luaNotified = false;
	std::chrono::milliseconds delayBeforeUnmute = std::chrono::milliseconds(1000);
	std::mutex mutex;
	std::chrono::time_point<std::chrono::system_clock> muteKeyReleasedTime = std::chrono::system_clock::now();
	void fetchResults();
	HRESULT NotifyCallback(WPARAM wParam, LPARAM lParam) override;
	HANDLE newResultsEvent = CreateEvent(0, 0, 0, 0);

public:

	HANDLE event();
	RecoResultFetcher(std::shared_ptr<Recognizer>);
	void registerCallback();
	void onMuteKey(bool state);
	std::vector<RecoResult> getResults();
};