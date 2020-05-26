#include "RecoResultFetcher.h"
#include "Copilot.h"
#include "FSUIPC/include/FSUIPC_User64.h"

RecoResultFetcher::RecoResultFetcher(Recognizer* recognizer)
	:m_recognizer(recognizer)
{
}

bool RecoResultFetcher::registerCallback()
{
	return m_recognizer->registerCallback(this);
}

void RecoResultFetcher::onMuteKeyEvent(bool isMuteKeyPressed)
{
	std::lock_guard<std::mutex> lock(m_mutex);
	if (!isMuteKeyPressed) {
		m_muteKeyReleasedTime = std::chrono::system_clock::now();
		copilot::logger->info("Unmuted");
	} else { 
		m_muted = true;
		copilot::logger->info("Muted");
	}
}

void RecoResultFetcher::notifyLua()
{
	const char* request = "LuaToggle FSLabs Copilot";
	uint32_t param = 0;
	DWORD dwResult;
	std::lock_guard<std::mutex> lock(copilot::FSUIPCmutex);
	FSUIPC_Write(0x0D6C, sizeof(param), (void*)&param, &dwResult);
	FSUIPC_Write(0x0D70, strlen(request) + 1, (void*)request, &dwResult);
	FSUIPC_Process(&dwResult);
}

void RecoResultFetcher::fetchResults()
{
	RecoResult recoResult = m_recognizer->getResult();
	if (recoResult.ruleID > 0) {
		std::lock_guard<std::mutex> lock(m_mutex);
		if (m_muted && std::chrono::system_clock::now() - m_muteKeyReleasedTime > m_delayBeforeUnmute)
			m_muted = false;
		if (!m_muted) {
			copilot::logger->info("Recognized phrase '{}', confidence: {:.4f}", recoResult.phrase, recoResult.confidence);
			m_recoResults.emplace_back(recoResult.ruleID);
			if (!copilot::simConnect->simPaused && !m_luaNotified) {
				notifyLua();
				m_luaNotified = true;
			}
		}
	}
}

sol::as_table_t<std::vector<RuleID>> RecoResultFetcher::getResults()
{
	std::lock_guard<std::mutex> lock(m_mutex);
	std::vector<RuleID> results = m_recoResults;
	m_recoResults.clear();
	m_luaNotified = false;
	return results;
}

HRESULT RecoResultFetcher::NotifyCallback(WPARAM wParam, LPARAM lParam)
{
	fetchResults();
	return 0;
}