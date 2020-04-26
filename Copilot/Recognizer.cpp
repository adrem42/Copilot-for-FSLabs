#include "Recognizer.h"
#include "Copilot.h"

void checkResult(const std::string& msg, HRESULT hr)
{
	//copilot::logger->debug("{}, result={}", msg, std::to_string(hr));
}

Recognizer::Recognizer()
{
	HRESULT hr;
	hr = CoInitialize(NULL);
	checkResult("CoInitialize", hr);


	if (SUCCEEDED(hr)) {
		hr = recognizer.CoCreateInstance(CLSID_SpInprocRecognizer);
		checkResult("Creating recognizer", hr);
	}
		

	if (SUCCEEDED(hr)) {
		hr = SpCreateDefaultObjectFromCategoryId(SPCAT_AUDIOIN, &audio);
		checkResult("SpCreateDefaultObjectFromCategoryId", hr);
	}
		

	if (SUCCEEDED(hr)) {
		hr = recognizer->SetInput(audio, TRUE);
		checkResult("SetInput", hr);
	}
		

	if (SUCCEEDED(hr)) {
		hr = recognizer->CreateRecoContext(&recoContext);
		checkResult("Creating reco context", hr);
	}
		

	if (SUCCEEDED(hr)) {
		recoContext->CreateGrammar(0, &recoGrammar);
		checkResult("Creating grammar", hr);
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
}

DWORD Recognizer::addRule(std::vector<std::string> phrases, float confidence)
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
	checkResult("Activating rule", hr);
	rules[ruleID - 1].state = Active;
}

void Recognizer::deactivateRule(DWORD ruleID)
{
	recoGrammar->SetRuleIdState(ruleID, SPRS_INACTIVE);
	rules[ruleID - 1].state = Inactive;
}

void Recognizer::resetGrammar()
{
	HRESULT hr;
	//copilot::logger->debug("Resetting grammar: ");
	hr = recognizer->SetRecoState(SPRST_INACTIVE);
	checkResult("Deactivating reco state", hr);
	hr = recoContext->Pause(NULL);
	checkResult("Pausing reco context", hr);
	hr = recognizer->SetRecoState(SPRST_ACTIVE);
	checkResult("Reactivating reco state", hr);
	if (SUCCEEDED(hr)) {
		hr = recoGrammar->ResetGrammar(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US));
		checkResult("Trying English-US", hr);
		if (FAILED(hr)) {
			hr = recoGrammar->ResetGrammar(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_UK));
			checkResult("Trying English-UK", hr);
		}
			
	}

	if (SUCCEEDED(hr)) {
		std::lock_guard<std::mutex> lock(mtx);
		for (const auto& rule : rules) {
			for (const auto& phrase : rule.phrases) {
				SPSTATEHANDLE initialState;
				hr = recoGrammar->GetRule(NULL, rule.ruleID, SPRAF_TopLevel | SPRAF_Active | SPRAF_Dynamic, TRUE, &initialState);
				checkResult("Creating rule", hr);
				if (SUCCEEDED(hr)) {
					std::wstring phraseWstr = std::wstring(phrase.begin(), phrase.end());
					hr = recoGrammar->AddWordTransition(initialState, NULL, phraseWstr.c_str(), L" ", SPWT_LEXICAL, 1, NULL);
					checkResult("AddWordTransition", hr);
				}
			}
		}
	}
	hr = recoGrammar->Commit(NULL);
	checkResult("Commiting grammar", hr);
	hr = recoContext->Resume(NULL);
	checkResult("Resuming reco context", hr);
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
