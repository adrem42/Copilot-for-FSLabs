#include "Recognizer.h"
#include "Copilot.h"
#include <sstream>

void checkResult(const std::string& msg, HRESULT hr)
{
	if (FAILED(hr)) {
		std::stringstream ss;
		ss << "0x" << std::hex << hr;
		copilot::logger->error("{}: {}", msg, ss.str());
	}
}

Recognizer::Recognizer()
{
	HRESULT hr;
	hr = CoInitialize(NULL);
	checkResult("CoInitialize error", hr);

	if (SUCCEEDED(hr)) {
		hr = recognizer.CoCreateInstance(CLSID_SpInprocRecognizer);
		checkResult("Error creating recognizer", hr);
	}
		
	if (SUCCEEDED(hr)) {
		hr = SpCreateDefaultObjectFromCategoryId(SPCAT_AUDIOIN, &audio);
		checkResult("Error in SpCreateDefaultObjectFromCategoryId", hr);
	}
		
	if (SUCCEEDED(hr)) {
		hr = recognizer->SetInput(audio, TRUE);
		checkResult("Error in SetInput", hr);
	}

	if (SUCCEEDED(hr)) {
		hr = recognizer->CreateRecoContext(&recoContext);
		checkResult("Error creating reco context", hr);
	}
		
	if (SUCCEEDED(hr)) {
		hr = recoContext->CreateGrammar(0, &recoGrammar);
		checkResult("Error creating grammar", hr);
	}
		
	if (!SUCCEEDED(hr))
		throw std::exception();
}

Recognizer::~Recognizer()
{
	recognizer->SetRecoState(SPRST_INACTIVE);
	recoContext->Pause(NULL);
	recoGrammar.Release();
	recoContext.Release();
	recognizer.Release();
	CoUninitialize();
}

DWORD Recognizer::addRule(const std::vector<std::string> phrases, float confidence)
{
	std::lock_guard<std::mutex> lock(mtx);
	rules.emplace_back(Rule{ phrases, confidence, ++ruleID });
	return ruleID;
}

void Recognizer::ignoreRule(DWORD ruleID)
{
	std::lock_guard<std::mutex> lock(mtx);
	recoGrammar->SetRuleIdState(ruleID, SPRS_ACTIVE);
	rules[ruleID - 1].state = Ignore;
}

void Recognizer::activateRule(DWORD ruleID)
{
	std::lock_guard<std::mutex> lock(mtx);
	HRESULT hr = recoGrammar->SetRuleIdState(ruleID, SPRS_ACTIVE);
	checkResult("Error activating rule", hr);
	rules[ruleID - 1].state = Active;
}

void Recognizer::deactivateRule(DWORD ruleID)
{
	recoGrammar->SetRuleIdState(ruleID, SPRS_INACTIVE);
	rules[ruleID - 1].state = Inactive;
}

sol::as_table_t<std::vector<std::string>> Recognizer::getPhrases(DWORD ruleID)
{
	return rules[ruleID - 1].phrases;
}

void Recognizer::addPhrase(const std::string& phrase, DWORD ruleID)
{
	auto& phrases = rules[ruleID - 1].phrases;
	phrases.emplace_back(phrase);
}

void Recognizer::removePhrase(const std::string& phrase, DWORD ruleID)
{
	auto& phrases = rules[ruleID - 1].phrases;
	auto it = std::find(phrases.begin(), phrases.end(), phrase);
	if (it != phrases.end())
		phrases.erase(it);
}

void Recognizer::removeAllPhrases(DWORD ruleID)
{
	rules[ruleID - 1].phrases.clear();
}

void Recognizer::setConfidence(float confidence, DWORD ruleID)
{
	rules[ruleID - 1].confidence = confidence;
}

void Recognizer::resetGrammar()
{
	HRESULT hr;
	hr = recognizer->SetRecoState(SPRST_INACTIVE);
	checkResult("Error deactivating reco state", hr);
	hr = recoContext->Pause(NULL);
	checkResult("Error pausing reco context", hr);
	hr = recognizer->SetRecoState(SPRST_ACTIVE);
	checkResult("Error reactivating reco state", hr);

	if (SUCCEEDED(hr)) {
		hr = recoGrammar->ResetGrammar(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US));
		if (FAILED(hr)) {
			hr = recoGrammar->ResetGrammar(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_UK));
			checkResult("Error resetting grammar", hr);
		}	
	}

	if (SUCCEEDED(hr)) {
		std::lock_guard<std::mutex> lock(mtx);
		for (const auto& rule : rules) {
			for (const auto& phrase : rule.phrases) {
				SPSTATEHANDLE initialState;
				hr = recoGrammar->GetRule(NULL, rule.ruleID, SPRAF_TopLevel | SPRAF_Active | SPRAF_Dynamic, TRUE, &initialState);
				checkResult("Error creating rule", hr);
				if (SUCCEEDED(hr)) {
					std::wstring phraseWstr = std::wstring(phrase.begin(), phrase.end());
					hr = recoGrammar->AddWordTransition(initialState, NULL, phraseWstr.c_str(), L" ", SPWT_LEXICAL, 1, NULL);
					checkResult("Error in AddWordTransition", hr);
				}
			}
		}
	}

	hr = recoGrammar->Commit(NULL);
	checkResult("Error while commiting grammar", hr);
	hr = recoContext->Resume(NULL);
	checkResult("Error while resuming reco context", hr);
	for (const auto& rule : rules) {
		if (rule.state == Active) activateRule(rule.ruleID);
		else if (rule.state == Ignore) ignoreRule(rule.ruleID);
	}
}

std::optional<RecoResult> Recognizer::getResult()
{
	CSpEvent event;
	if (event.GetFrom(recoContext) == S_OK) {
		if (event.eEventId == SPEI_RECOGNITION) {
			HRESULT hr;
			CSpDynamicString dstrText;
			SPPHRASE* spphrase;
			auto _recoResult = event.RecoResult();
			hr = _recoResult->GetPhrase(&spphrase);
			if (SUCCEEDED(hr))
				_recoResult->GetText(SP_GETWHOLEPHRASE, SP_GETWHOLEPHRASE, TRUE, &dstrText, NULL);
			if (SUCCEEDED(hr)) {
				DWORD ruleID = spphrase->Rule.ulId;
				float confidence = spphrase->pElements->SREngineConfidence;
				std::string phrase = dstrText.CopyToChar();
				std::lock_guard<std::mutex> lock(mtx);
				const Rule& rule = rules[ruleID - 1];
				if (rule.state != Ignore && confidence >= rule.confidence) {
					return RecoResult {phrase, confidence, ruleID};
				}
			}
		}
	}
	return {};
}
