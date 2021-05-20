#pragma once
#include <lua.hpp>
#include <chrono>
#include <atomic>
#include <vector>
#include <Windows.h>
#include "Recognizer.h"
#include "functional"

class RecoResultFetcher : ISpNotifyCallback {
	const std::shared_ptr<Recognizer> recognizer;
	std::vector<RecoResult> recoResults;
	std::mutex mutex;
	void fetchResults();
	HRESULT NotifyCallback(WPARAM wParam, LPARAM lParam) override;
	HANDLE newResultsEvent = CreateEvent(0, 0, 0, 0);
public:
	HANDLE event();
	RecoResultFetcher(std::shared_ptr<Recognizer>);
	void registerCallback();
	std::vector<RecoResult> getResults();
};