#include "Recognizer.h"
#include "Copilot.h"
#include <sstream>
#include <map>
#include <vector>

Recognizer::Phrase::PhraseElement::PhraseElement(std::vector<std::wstring>&& variants, std::wstring&& propName, bool optional)
	:optional(optional), propName(propName)
{
	for (const auto& variant : variants) {
		size_t pos = variant.find('=');
		if (pos != std::string::npos) {
			this->variants.emplace_back(Variant{ variant.substr(pos + 1, variant.length()), variant.substr(0, pos) });
		} else {
			this->variants.emplace_back(Variant{ variant, {} });
		}
	}
	if (optional)
		asString += L"[";
	if (variants.size() == 1) {
		asString += this->variants[0].value;
	} else {
		asString += L"{";
		for (size_t i = 0; i < this->variants.size(); ++i) {
			asString += this->variants[i].value;
			if (i < this->variants.size() - 1) {
				asString += L", ";
			}
		}
		asString += L"}";
	}
	if (optional)
		asString += L"]";
}

Recognizer::Phrase& Recognizer::Phrase::setName(const std::string& name)
{
	this->name = name;
	return *this;
}

Recognizer::Phrase& Recognizer::Phrase::append(std::wstring phraseElement, std::wstring propName, bool optional)
{
	return append(std::vector<std::wstring>{std::move(phraseElement)}, std::move(propName), optional);
}

Recognizer::Phrase& Recognizer::Phrase::append(std::wstring phraseElement, bool optional)
{
	std::wstring propName;
	return append(phraseElement, propName, optional);
}

Recognizer::Phrase& Recognizer::Phrase::append(std::wstring phraseElement)
{
	return append(phraseElement, false);
}

Recognizer::Phrase& Recognizer::Phrase::append(std::vector<std::wstring> elements, std::wstring propName, bool optional)
{
	if (!phraseElements.empty())
		asString += L" ";
	auto& el = phraseElements.emplace_back(std::move(elements), std::move(propName), optional);
	asString += el.asString;
	return *this;
}

Recognizer::Phrase& Recognizer::Phrase::append(std::vector<std::wstring> elements, std::wstring propName)
{
	return append(std::move(elements), propName, false);
}

Recognizer::Phrase& Recognizer::Phrase::append(std::vector<std::wstring> variants, bool optional)
{
	std::wstring propName;
	return append(std::move(variants), propName, optional);
}

Recognizer::Phrase& Recognizer::Phrase::append(std::vector<std::wstring> variants)
{
	return append(std::move(variants), false);
}

bool checkResult(const std::string& msg, HRESULT hr)
{
	if (SUCCEEDED(hr)) return true;
	copilot::logger->error("{}: 0x{:X}", msg, (unsigned long)hr);
	return false;
}

void throwOnBadResult(const std::string& msg, HRESULT hr)
{
	if (SUCCEEDED(hr)) return;
	throw std::runtime_error(fmt::format("{}: 0x{:X}", msg, (unsigned long)hr));
}

Recognizer::Recognizer()
{

	throwOnBadResult("CoInitialize error", CoInitialize(NULL));

	throwOnBadResult(
		"Error creating recognizer",
		recognizer.CoCreateInstance(CLSID_SpInprocRecognizer)
	);

	throwOnBadResult(
		"Error in SpCreateDefaultObjectFromCategoryId",
		SpCreateDefaultObjectFromCategoryId(SPCAT_AUDIOIN, &audio)
	);

	throwOnBadResult("Error in SetInput", recognizer->SetInput(audio, TRUE));

	throwOnBadResult("Error creating reco context", recognizer->CreateRecoContext(&recoContext));

	ULONGLONG interest = SPFEI(SPEI_RECOGNITION);

	throwOnBadResult("Error in SetInterest", recoContext->SetInterest(interest, interest));

	throwOnBadResult("Error creating grammar", recoContext->CreateGrammar(0, &recoGrammar));
	
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

void Recognizer::registerCallback(ISpNotifyCallback* callback)
{
	throwOnBadResult(
		"Error setting up notification callback",
		recoContext->SetNotifyCallbackInterface(callback, 0, 0)
	);
}

RuleID Recognizer::addRule(std::vector<Phrase> phrases, float confidence, RulePersistenceMode persistenceMode)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	CurrRuleId++;
	rules.emplace(CurrRuleId, std::move(Rule{ phrases, confidence, CurrRuleId, persistenceMode}));
	return CurrRuleId;
}

Recognizer::Rule& Recognizer::getRuleById(RuleID ruleID)
{
	return rules[ruleID];
}

void Recognizer::logRuleStatus(std::string& prefix, const Rule& rule)
{
	copilot::logger->debug(L"{} rule ID {} ({})", std::wstring(prefix.begin(), prefix.end()), rule.ruleID,
						   rule.phrases.empty() ? L"rule has no phrase variants" : L"phrase #1: '" + rule.phrases[0].asString + L"'");
}

void Recognizer::changeRuleState(Rule& rule, RuleState newRuleState, SPRULESTATE spRuleState, std::string&& logMsg, std::string&& dummyLogMsg)
{
	HRESULT hr;
	if (rule.dummyRuleID) {
		Rule& dummyRule = getRuleById(rule.dummyRuleID);
		if (dummyRule.sapiRuleState != spRuleState) {
			logRuleStatus(dummyLogMsg, dummyRule);
			hr = recoGrammar->SetRuleIdState(dummyRule.ruleID, spRuleState);
			checkResult("Error changing rule state", hr);
			dummyRule.sapiRuleState = spRuleState;
		}
	}
	logRuleStatus(logMsg, rule);
	if (rule.sapiRuleState != spRuleState) {
		hr = recoGrammar->SetRuleIdState(rule.ruleID, spRuleState);
		checkResult("Error changing rule state", hr);
		rule.sapiRuleState = spRuleState;
	}
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

Recognizer::RuleState Recognizer::getRuleState(RuleID ruleID)
{
	return getRuleById(ruleID).state;
}

sol::as_table_t<std::vector<Recognizer::Phrase>> Recognizer::getPhrases(RuleID ruleID, bool dummy = false)
{
	Rule& rule = getRuleById(ruleID);
	if (dummy) {
		if (rule.dummyRuleID) return getRuleById(rule.dummyRuleID).phrases;
		return {};
	}
	return getRuleById(ruleID).phrases;
}

void Recognizer::addPhrases(std::vector<Phrase> phrases, RuleID ruleID, bool dummy = false)
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

//void Recognizer::removePhrases(std::vector<std::string> phrases, RuleID ruleID, bool dummy = false)
//{
//	Rule& rule = getRuleById(ruleID);
//	std::vector<std::string>* _phrases;
//	if (dummy) {
//		if (!rule.dummyRuleID) return;
//		_phrases = &getRuleById(rule.dummyRuleID).phrases;
//	} else {
//		_phrases = &rule.phrases;
//	}
//	for (auto&& phrase : phrases) {
//		auto it = std::find(_phrases->begin(), _phrases->end(), phrase);
//		if (it != _phrases->end()) _phrases->erase(it);
//	}
//}

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

	if (rules.empty()) return;

	copilot::logger->debug("Resetting grammar and reloading grammar rules...");
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

	std::unordered_map<Rule*, RuleState> statesBefore;

	if (SUCCEEDED(hr)) {
		std::lock_guard<std::recursive_mutex> lock(mtx);
		/*for (auto& [_, rule] : rules) {
			statesBefore[&rule] = rule.state;
			if (rule.state != RuleState::Disabled)
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
		}*/

		for (auto& [_, rule] : rules) {

			statesBefore[&rule] = rule.state;

			if (rule.state != RuleState::Disabled) {
				rule.state = RuleState::Inactive;
				rule.sapiRuleState = SPRS_INACTIVE;
			}

			for (Phrase& phrase : rule.phrases) {

				auto& phraseElements = phrase.phraseElements;
				size_t numElements = phraseElements.size();

				if (numElements > 0) {

					hr = recoGrammar->GetRule(NULL, rule.ruleID, SPRAF_TopLevel | SPRAF_Active | SPRAF_Dynamic, TRUE, &phraseElements[0].state);
					checkResult("Error creating rule", hr);
					if (SUCCEEDED(hr)) {
						for (size_t i = 0; i < numElements;) {
							auto& phraseElement = phraseElements[i];
							SPSTATEHANDLE currState = phraseElement.state;
							SPSTATEHANDLE nextState = NULL;
							if (++i < numElements) {
								recoGrammar->CreateNewState(currState, &phraseElements[i].state);
								nextState = phraseElements[i].state;
							}
							SPPROPERTYINFO prop{};
							SPPROPERTYINFO* pProp = NULL;
							if (phraseElement.propName != L"") {
								pProp = &prop;
								prop.pszName = phraseElement.propName.c_str();
							}
							for (auto& variant : phraseElement.variants) {
								if (prop.pszName) {
									prop.pszValue = variant.name ? variant.name.value().c_str() : variant.value.c_str();
								}
								hr = recoGrammar->AddWordTransition(currState, nextState, variant.value.c_str(), L" ", SPWT_LEXICAL, 1.0f, pProp);
								checkResult("Error in AddWordTransition", hr);
							}
							if (phraseElement.optional) {
								hr = recoGrammar->AddWordTransition(currState, nextState, NULL, L" ", SPWT_LEXICAL, 1.0f, pProp);
							}
						}
					}
				}
			}
		}
	}

	hr = recoGrammar->Commit(NULL);
	checkResult("Error while commiting grammar", hr);
	hr = recoContext->Resume(NULL);
	checkResult("Error while resuming reco context", hr);

	for (auto& [rule, state] : statesBefore) {
		switch (state) {
			case RuleState::Active:
				activateRule(rule->ruleID);
				break;
			case RuleState::Ignore:
				ignoreRule(rule->ruleID);
				break;
		}
	}
}

void Recognizer::afterRecoEvent(RuleID ruleID)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	switch (getRuleById(ruleID).persistenceMode) {
		case RulePersistenceMode::Ignore:
			ignoreRule(ruleID);
			break;
		case RulePersistenceMode::NonPersistent:
			deactivateRule(ruleID);
			break;
	}
}

void Recognizer::makeLuaBindings(sol::state_view& lua)
{
	auto RecognizerType = lua.new_usertype<Recognizer>("Recognizer");
	RecognizerType["addRule"] = &Recognizer::addRule;
	RecognizerType["activateRule"] = &Recognizer::activateRule;
	RecognizerType["deactivateRule"] = &Recognizer::deactivateRule;
	RecognizerType["ignoreRule"] = &Recognizer::ignoreRule;
	RecognizerType["disableRule"] = &Recognizer::disableRule;
	RecognizerType["resetGrammar"] = &Recognizer::resetGrammar;
	RecognizerType["addPhrases"] = &Recognizer::addPhrases;
	//RecognizerType["removePhrases"] = &Recognizer::removePhrases;
	RecognizerType["removeAllPhrases"] = &Recognizer::removeAllPhrases;
	RecognizerType["setConfidence"] = &Recognizer::setConfidence;
	RecognizerType["getPhrases"] = &Recognizer::getPhrases;
	RecognizerType["setRulePersistence"] = &Recognizer::setRulePersistence;
	RecognizerType["getRuleState"] = &Recognizer::getRuleState;
	lua.new_enum("RulePersistenceMode",
				 "Ignore", Recognizer::RulePersistenceMode::Ignore,
				 "Persistent", Recognizer::RulePersistenceMode::Persistent,
				 "NonPersistent", Recognizer::RulePersistenceMode::NonPersistent);

	auto PhraseType = lua.new_usertype<Phrase>("Phrase");
	PhraseType["append"] = sol::overload(
		static_cast<Phrase&(Phrase::*)(std::vector<std::wstring> elements, std::wstring propName, bool optional)>(&Phrase::append),
		static_cast<Phrase & (Phrase::*)(std::vector<std::wstring> elements, std::wstring propName)>(&Phrase::append),
		static_cast<Phrase&(Phrase::*)(std::wstring, std::wstring propName, bool optional)>(&Phrase::append),
		static_cast<Phrase&(Phrase::*)(std::wstring phraseElement, bool optional)>(&Phrase::append),
		static_cast<Phrase&(Phrase::*)(std::wstring phraseElement)>(&Phrase::append),
		static_cast<Phrase&(Phrase::*)(std::vector<std::wstring> elements, bool optional)>(&Phrase::append),
		static_cast<Phrase&(Phrase::*)(std::vector<std::wstring> elements)>(&Phrase::append)
	);
	PhraseType[sol::meta_function::to_string] = [](const Phrase& phrase) {return phrase.asString; };

	auto ResultType = lua.new_usertype<RecoResult>("RecoResult");
	ResultType["props"] = sol::readonly_property([](RecoResult& res) {return res.props; });
	ResultType["confidence"] = sol::readonly_property([](RecoResult& res) {return res.confidence; });
	ResultType["phrase"] = sol::readonly_property([](RecoResult& res) {return res.phrase; });
	
	lua.new_enum<RuleState>(
		"RuleState",
		{
			{"Active", RuleState::Active},
			{"Inactive", RuleState::Inactive},
			{"Ignore", RuleState::Ignore},
			{"Disabled", RuleState::Disabled}
		}
	);
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
			float confidence = spphrase->Rule.SREngineConfidence;
			std::wstring phrase = dstrText.Copy();
			std::lock_guard<std::recursive_mutex> lock(mtx);
			const Rule& rule = getRuleById(ruleID);
			if (rule.state != RuleState::Ignore && confidence >= rule.confidence) {
				std::unordered_map<std::wstring, std::wstring> props;
				const SPPHRASEPROPERTY* prop = spphrase->pProperties;
				if (prop != nullptr) {
					do {
						props[prop->pszName] = prop->pszValue;
					} while (prop = prop->pNextSibling);
				}
				return RecoResult{ std::move(phrase), confidence, std::move(props), ruleID };
			}
		}
	}
	return {};
}
