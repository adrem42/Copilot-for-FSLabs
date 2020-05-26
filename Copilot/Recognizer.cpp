#include "Recognizer.h"
#include "Copilot.h"
#include <sstream>
#include <map>

bool checkResult(const std::string& msg, HRESULT hr)
{
	if (FAILED(hr)) {
		std::stringstream ss;
		ss << "0x" << std::hex << hr;
		copilot::logger->error("{}: {}", msg, ss.str());
		return false;
	}
	return true;
}

bool Recognizer::init()
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
		ULONGLONG interest = SPFEI(SPEI_RECOGNITION);
		hr = recoContext->SetInterest(interest, interest);
		checkResult("Error creating reco context", hr);
	}
	
	if (SUCCEEDED(hr)) {
		hr = recoContext->CreateGrammar(0, &recoGrammar);
		checkResult("Error creating grammar", hr);
	}
	
	return SUCCEEDED(hr);
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

bool Recognizer::registerCallback(ISpNotifyCallback* callback)
{
	HRESULT hr = recoContext->SetNotifyCallbackInterface(callback, 0, 0);
	return checkResult("Error setting up notification callback", hr);
}

RuleID Recognizer::addRule(std::vector<std::string> phrases, float confidence, RulePersistenceMode persistenceMode)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	rules.emplace_back(Rule{ phrases, confidence, ++CurrRuleId, persistenceMode});
	return CurrRuleId;
}

Recognizer::Rule& Recognizer::getRuleById(RuleID ruleID)
{
	return rules[ruleID - 1];
}

void Recognizer::logRuleStatus(std::string& prefix, const Rule& rule)
{
	copilot::logger->debug("{} rule ID {} ({})", prefix, rule.ruleID,
						   rule.phrases.empty() ? "rule has no phrase variants" : "phrase #1: '" + rule.phrases[0] + "'");
}

void Recognizer::changeRuleState(Rule& rule, RuleState newRuleState, SPRULESTATE spRuleState, std::string&& logMsg, std::string&& dummyLogMsg)
{
	HRESULT hr;
	if (rule.dummyRuleID) {
		Rule& dummyRule = getRuleById(rule.dummyRuleID);
		logRuleStatus(dummyLogMsg, dummyRule);
		hr = recoGrammar->SetRuleIdState(dummyRule.ruleID, spRuleState);
		checkResult("Error changing rule state", hr);
	}
	logRuleStatus(logMsg, rule);
	hr = recoGrammar->SetRuleIdState(rule.ruleID, spRuleState);
	checkResult("Error changing rule state", hr);
	rule.state = newRuleState;
	return;
}

void Recognizer::activateRule(RuleID ruleID)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	Rule& rule = getRuleById(ruleID);
	switch (rule.state) {
		case RuleState::Disabled:
		case RuleState::Active:
			return;
		default:
			changeRuleState(rule, RuleState::Active, SPRS_ACTIVE, "Activating", "Activating dummy");
			return;
	}
}

void Recognizer::ignoreRule(RuleID ruleID)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	Rule& rule = getRuleById(ruleID);
	switch (rule.state) {
		case RuleState::Disabled:
		case RuleState::Ignore:
			return;
		default:
			changeRuleState(rule, RuleState::Ignore, SPRS_ACTIVE, "Setting ignore mode for", "Activating dummy");
			return;
	}
}

void Recognizer::deactivateRule(RuleID ruleID)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	Rule& rule = getRuleById(ruleID);
	switch (rule.state) {
		case RuleState::Disabled:
		case RuleState::Inactive:
			return;
		default:
			changeRuleState(rule, RuleState::Inactive, SPRS_INACTIVE, "Deactivating", "Deactivating dummy");
			return;
	}
}

void Recognizer::disableRule(RuleID ruleID)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	Rule& rule = getRuleById(ruleID);
	if (rule.state != RuleState::Disabled)
		changeRuleState(rule, RuleState::Disabled, SPRS_INACTIVE, "Disabling", "Disabling dummy");
}

sol::as_table_t<std::vector<std::string>> Recognizer::getPhrases(RuleID ruleID, bool dummy = false)
{
	Rule& rule = getRuleById(ruleID);
	if (dummy) {
		if (rule.dummyRuleID) return getRuleById(rule.dummyRuleID).phrases;
		return {};
	}
	return getRuleById(ruleID).phrases;
}

void Recognizer::addPhrases(std::vector<std::string> phrases, RuleID ruleID, bool dummy = false)
{
	Rule& rule = getRuleById(ruleID);
	if (dummy) {
		RuleID dummyRuleID = rule.dummyRuleID;
		if (!dummyRuleID) {
			rule.dummyRuleID = addRule(phrases, 1.0, RulePersistenceMode::Ignore);
		} else {
			Rule& dummyRule = getRuleById(dummyRuleID);
			dummyRule.phrases.insert(dummyRule.phrases.end(), phrases.begin(), phrases.end());
		}	
	} else {
		rule.phrases.insert(rule.phrases.end(), phrases.begin(), phrases.end());
	}
}

void Recognizer::removePhrases(std::vector<std::string> phrases, RuleID ruleID, bool dummy = false)
{
	Rule& rule = getRuleById(ruleID);
	std::vector<std::string>* _phrases;
	if (dummy) {
		if (!rule.dummyRuleID) return;
		_phrases = &getRuleById(rule.dummyRuleID).phrases;
	} else {
		_phrases = &rule.phrases;
	}
	for (auto&& phrase : phrases) {
		auto it = std::find(_phrases->begin(), _phrases->end(), phrase);
		if (it != _phrases->end()) _phrases->erase(it);
	}
}

void Recognizer::removeAllPhrases(RuleID ruleID, bool dummy = false)
{
	Rule& rule = getRuleById(ruleID);
	if (dummy) {
		if (!rule.dummyRuleID) return;
		getRuleById(rule.dummyRuleID).phrases.clear();
	} else {
		rule.phrases.clear();
	}
}

void Recognizer::setConfidence(float confidence, RuleID ruleID)
{
	getRuleById(ruleID).confidence = confidence;
}

void Recognizer::setRulePersistence(RulePersistenceMode persistenceMode, RuleID ruleID)
{
	getRuleById(ruleID).persistenceMode = persistenceMode;
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

	std::map<Rule*, RuleState> statesBefore;

	if (SUCCEEDED(hr)) {
		std::lock_guard<std::recursive_mutex> lock(mtx);
		for (auto& rule : rules) {
			statesBefore[&rule] = rule.state;
			rule.state = RuleState::Inactive;
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

	for (auto& ruleStatePair : statesBefore) {
		Rule* rule = ruleStatePair.first;
		RuleState stateBefore = ruleStatePair.second;
		switch (stateBefore) {
			case RuleState::Active:
				activateRule(rule->ruleID);
				break;
			case RuleState::Ignore:
				ignoreRule(rule->ruleID);
				break;
		}
	}
}

RecoResult Recognizer::getResult()
{
	CSpEvent event;
	if (event.GetFrom(recoContext) == S_OK && event.eEventId == SPEI_RECOGNITION) {
		HRESULT hr;
		CSpDynamicString dstrText;
		SPPHRASE* spphrase;
		auto _recoResult = event.RecoResult();
		hr = _recoResult->GetPhrase(&spphrase);
		if (SUCCEEDED(hr))
			hr = _recoResult->GetText(SP_GETWHOLEPHRASE, SP_GETWHOLEPHRASE, TRUE, &dstrText, NULL);
		if (SUCCEEDED(hr)) {
			RuleID ruleID = spphrase->Rule.ulId;
			float confidence = spphrase->pElements->SREngineConfidence;
			std::string phrase = dstrText.CopyToChar();
			std::lock_guard<std::recursive_mutex> lock(mtx);
			const Rule& rule = getRuleById(ruleID);
			if (rule.state != RuleState::Ignore && confidence >= rule.confidence) {
				switch (rule.persistenceMode) {
					case RulePersistenceMode::Ignore:
						ignoreRule(ruleID);
						break;
					case RulePersistenceMode::NonPersistent:
						deactivateRule(ruleID);
						break;
				}
				return RecoResult{ phrase, confidence, ruleID };
			}
		}
	}
	return {};
}
