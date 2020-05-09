#include "RecoResultFetcher.h"
#include "Copilot.h"

RecoResultFetcher::RecoResultFetcher(std::shared_ptr<Recognizer> recognizer)
	:recognizer(recognizer)
{
}

void RecoResultFetcher::onMuteKeyEvent(bool isMuteKeyPressed)
{
	std::lock_guard<std::mutex> lock(mtx);
	if (!isMuteKeyPressed) {
		muteKeyRelasedTime = std::chrono::system_clock::now();
		copilot::logger->info("Unmuted");
	} else { 
		muted = true;
		copilot::logger->info("Muted");
	}
}

void RecoResultFetcher::fetchResults()
{
	auto recoResult = recognizer->getResult();
	if (recoResult) {
		std::lock_guard<std::mutex> lock(mtx);
		if (muted && std::chrono::system_clock::now() - muteKeyRelasedTime > delayBeforeUnmute)
			muted = false;
		if (!muted) {
			copilot::logger->info("Recognized phrase '{}', confidence: {:.4f}", recoResult->phrase, recoResult->confidence);
			recoResults.emplace(recoResult->ruleID);
		}
	}
	
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