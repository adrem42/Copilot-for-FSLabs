#include "RecoResultFetcher.h"
#include "Copilot.h"
#include "SimConnect.h"
#include "FSUIPC_User64.h"

bool fslAircraftLoaded = false, simStarted = false;
HANDLE hSimConnect = NULL;
std::atomic_bool simPaused;

RecoResultFetcher::RecoResultFetcher(std::shared_ptr<Recognizer> recognizer)
	:recognizer(recognizer)
{
}

void RecoResultFetcher::registerCallback()
{
	recognizer->registerCallback(this);
}

void RecoResultFetcher::fetchResults()
{
	RecoResult recoResult = recognizer->getResult();
	if (recoResult.ruleID > 0) {
		std::lock_guard<std::mutex> lock(mutex);
		if (!copilot::isMuted() && recognizer->getRuleState(recoResult.ruleID) == Recognizer::RuleState::Active) {
			copilot::logger->info(L"Recognized '{}' (confidence {:.4f})", recoResult.phrase, recoResult.confidence);
			recognizer->afterRecoEvent(recoResult.ruleID);
			recoResults.emplace_back(std::move(recoResult));
			SetEvent(newResultsEvent);
		}
	}
}

HANDLE RecoResultFetcher::event()
{
	return newResultsEvent;
}

std::vector<RecoResult> RecoResultFetcher::getResults()
{
	std::lock_guard<std::mutex> lock(mutex);
	std::vector<RecoResult> results = recoResults;
	recoResults.clear();
	return results;
}

HRESULT RecoResultFetcher::NotifyCallback(WPARAM wParam, LPARAM lParam)
{
	fetchResults();
	return 0;
}