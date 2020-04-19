#include "RecoResultFetcher.h"
#include "Copilot.h"

RecoResultFetcher::RecoResultFetcher(std::shared_ptr<Recognizer> recognizer)
	:recognizer(recognizer)
{
}

void RecoResultFetcher::fetchResults()
{
	auto recoResult = recognizer->getResult();
	if (recoResult && !muted) {
		copilot::logger->info("Recognized phrase '{}', confidence: {:.4f}", recoResult->phrase, recoResult->confidence);
		std::lock_guard<std::mutex> lock(mtx);
		recoResults.emplace(recoResult->ruleID);
	}
	auto now = std::chrono::system_clock::now();
	if (isMuteKeyPressed && !wasMuteKeyPressed) {
		wasMuteKeyPressed = true;
		muted = true;
	} else if (!isMuteKeyPressed && wasMuteKeyPressed) {
		wasMuteKeyPressed = false;
		muteKeyReleasedTime = now;
	}
	if (muted && !wasMuteKeyPressed && now - muteKeyReleasedTime > std::chrono::milliseconds(delayBeforeUnmute))
		muted = false;
}

std::optional<DWORD> RecoResultFetcher::getResult()
{
	std::lock_guard<std::mutex> lock(mtx);
	if (!recoResults.empty()) {
		auto res = recoResults.front();
		recoResults.pop();
		return res;
	}
	return {};
}