#pragma once
#include <lua.hpp>
#include <chrono>
#include <atomic>
#include <vector>
#include <Windows.h>
#include "Recognizer.h"
#include "functional"

class RecognizerCallback : ISpNotifyCallback {
public:
	using Callback = std::function<void(RecoResult&)>;
private:
	Callback callback;
	std::shared_ptr<Recognizer> recognizer;
	void fetchResults();
	HRESULT NotifyCallback(WPARAM wParam, LPARAM lParam) override;
	std::optional<std::string> muteKeyEvent;
	size_t muteKeyEventCallbackId;
	bool muteKeyDepressed = false;
	std::chrono::milliseconds delayBeforeUnmute = std::chrono::milliseconds(1000);
	std::chrono::time_point<std::chrono::system_clock> muteKeyReleasedTime = std::chrono::system_clock::now();
	std::thread callbackThread;
	bool isMuted();
public:
	RecognizerCallback(std::shared_ptr<Recognizer>, Callback cb, std::optional<std::string> = std::nullopt);
	void start();
	~RecognizerCallback();
};