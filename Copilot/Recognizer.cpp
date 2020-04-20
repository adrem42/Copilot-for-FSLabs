#include "Recognizer.h"

Recognizer::Recognizer()
{
	HRESULT hr;
	hr = CoInitialize(NULL);
	if (SUCCEEDED(hr))
		hr = recognizer.CoCreateInstance(CLSID_SpInprocRecognizer);

	if (SUCCEEDED(hr))
		hr = SpCreateDefaultObjectFromCategoryId(SPCAT_AUDIOIN, &audio);

	if (SUCCEEDED(hr))
		hr = recognizer->SetInput(audio, TRUE);

	if (SUCCEEDED(hr))
		hr = recognizer->CreateRecoContext(&recoContext);

	if (SUCCEEDED(hr))
		recoContext->CreateGrammar(0, &recoGrammar);

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
	rules[ruleID - 1].ignore = true;
}

void Recognizer::activateRule(DWORD ruleID)
{
	std::lock_guard<std::mutex> lock(mtx);
	recoGrammar->SetRuleIdState(ruleID, SPRS_ACTIVE);
	rules[ruleID - 1].ignore = false;
}

void Recognizer::deactivateRule(DWORD ruleID)
{
	recoGrammar->SetRuleIdState(ruleID, SPRS_INACTIVE);
}

void Recognizer::resetGrammar()
{
	HRESULT hr;
	hr = recognizer->SetRecoState(SPRST_INACTIVE);
	hr = recoContext->Pause(NULL);
	hr = recognizer->SetRecoState(SPRST_ACTIVE);
	if (SUCCEEDED(hr)) {
		hr = recoGrammar->ResetGrammar(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US));
		if (FAILED(hr))
			hr = recoGrammar->ResetGrammar(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_UK));
	}

	if (SUCCEEDED(hr)) {
		std::lock_guard<std::mutex> lock(mtx);
		for (const auto& rule : rules) {
			for (const auto& phrase : rule.phrases) {
				SPSTATEHANDLE initialState;
				hr = recoGrammar->GetRule(NULL, rule.ruleID, SPRAF_TopLevel | SPRAF_Active | SPRAF_Dynamic, TRUE, &initialState);
				if (SUCCEEDED(hr)) {
					std::wstring phraseWstr = std::wstring(phrase.begin(), phrase.end());
					hr = recoGrammar->AddWordTransition(initialState, NULL, phraseWstr.c_str(), L" ", SPWT_LEXICAL, 1, NULL);
				}
			}
		}
	}
	recoGrammar->Commit(NULL);
	recoContext->Resume(NULL);
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
				if (!rule.ignore && confidence >= rule.confidence) {
					return RecoResult {phrase, confidence, ruleID};
				}
			}
		}
	}
	return {};
}
