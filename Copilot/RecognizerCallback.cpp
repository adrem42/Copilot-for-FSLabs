#include "RecognizerCallback.h"
#include "Copilot.h"
#include "SimConnect.h"
#include "FSUIPC_User64.h"

bool fslAircraftLoaded = false, simStarted = false;
HANDLE hSimConnect = NULL;
std::atomic_bool simPaused;

bool RecognizerCallback::isMuted()
{
	if (muteKeyDepressed)
		return true;
	return std::chrono::system_clock::now() - muteKeyReleasedTime < delayBeforeUnmute;
}

RecognizerCallback::RecognizerCallback(std::shared_ptr<Recognizer> recognizer, Callback callback, std::optional<std::string> muteKeyEvent)
	:recognizer(recognizer), callback(callback), muteKeyEvent(muteKeyEvent)
{
	if (muteKeyEvent) {
		auto evt = SimConnect::getNamedEvent(muteKeyEvent.value());
		muteKeyEventCallbackId = evt->addCallback([&](DWORD isPressed) {
			if (!isPressed && muteKeyDepressed) {
				muteKeyReleasedTime = std::chrono::system_clock::now();
			}
			this->muteKeyDepressed = isPressed;
		});
	}
}

void RecognizerCallback::start() {
	callbackThread = std::thread([&] {
		recognizer->registerCallback(this);
		MSG msg = {};
		while (GetMessage(&msg, NULL, 0, 0)) {
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	});
}

RecognizerCallback::~RecognizerCallback()
{
	if (muteKeyEvent) {
		auto evt = SimConnect::getNamedEvent(muteKeyEvent.value());
		evt->removeCallback(muteKeyEventCallbackId);
	}
	if (callbackThread.joinable()) {
		PostThreadMessage(GetThreadId(callbackThread.native_handle()),
						WM_QUIT, 0, 0);
		callbackThread.join();
	}
}

void RecognizerCallback::fetchResults()
{
	RecoResult recoResult = recognizer->getResult();
	if (recoResult.ruleID > 0) {
		if (!this->isMuted() && recognizer->getRuleState(recoResult.ruleID) == Recognizer::RuleState::Active) {
			recognizer->afterRecoEvent(recoResult.ruleID);
			callback(recoResult);
		}
	}
}

HRESULT RecognizerCallback::NotifyCallback(WPARAM wParam, LPARAM lParam)
{
	fetchResults();
	return 0;
}

