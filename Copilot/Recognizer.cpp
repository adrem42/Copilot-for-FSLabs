#include "Recognizer.h"
#include "Copilot.h"
#include <sstream>
#include <map>
#include <vector>

const int IDX_STRING = 0;

Recognizer::Phrase::PhraseElement::Variant::Variant(VariantValue val, std::wstring name)
	:value(val), name(name)
{
	if (val.index() == IDX_STRING)  {
		asString = std::get<std::wstring>(val);
	} else {
		asString = std::get<std::shared_ptr<Phrase>>(val)->asString;
	}
}

Recognizer::Phrase::PhraseElement::PhraseElement(std::vector<Variant> variants, std::wstring propName, bool optional)
	:optional(optional), propName(propName), variants(variants)
{
	if (optional)
		asString += L"[";
	if (variants.size() == 1) {
		asString += this->variants[0].asString;
	} else {
		asString += L"{";
		for (size_t i = 0; i < this->variants.size(); ++i) {
			asString += this->variants[i].asString;
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

Recognizer::Phrase& Recognizer::Phrase::append(std::wstring phraseElement)
{
	return append(std::vector<PhraseElement::Variant>{std::move(PhraseElement::Variant(phraseElement))}, L"", false);
}

Recognizer::Phrase& Recognizer::Phrase::appendOptional(VariantValue phraseElement)
{
	return append(std::vector<PhraseElement::Variant>{std::move(PhraseElement::Variant(phraseElement))}, L"", true);
}

Recognizer::Phrase& Recognizer::Phrase::appendOptional(VariantValue phraseElement, std::wstring propName)
{
	return append(std::vector<PhraseElement::Variant>{std::move(PhraseElement::Variant(phraseElement))}, propName, true);
}

Recognizer::Phrase& Recognizer::Phrase::append(LuaVariantMap phraseElement)
{
	return append(phraseElement, L"");
}

Recognizer::Phrase& Recognizer::Phrase::append(LuaVariantMap phraseElement, std::wstring propName)
{
	return append(phraseElement, propName, false);
}

Recognizer::Phrase& Recognizer::Phrase::appendOptional(LuaVariantMap phraseElement)
{
	return append(phraseElement, L"", true);
}

Recognizer::Phrase& Recognizer::Phrase::appendOptional(LuaVariantMap phraseElement, std::wstring propName)
{
	return append(phraseElement, propName, true);
}

Recognizer::Phrase& Recognizer::Phrase::append(LuaVariantMap phraseElement, std::wstring propName, bool optional, std::wstring asString)
{
	std::vector<PhraseElement::Variant> variants;

	for (auto& element : phraseElement) {
		std::wstring name;
		VariantValue varValue;
		sol::object stringOrPhrase;
		if (element.get_type() == sol::type::table) {
			sol::table t = element;
			if (t["propVal"].get_type() == sol::type::string)
				name = t.get<std::wstring>("propVal");
			stringOrPhrase = t["variant"];
		} else {
			stringOrPhrase = element;
		}
		if (stringOrPhrase.get_type() == sol::type::string) {
			varValue = stringOrPhrase.as<std::wstring>();
		} else {
			varValue = std::shared_ptr<Phrase>(new Phrase(stringOrPhrase.as<Phrase>()));
		}
		variants.emplace_back(varValue, name);
	}

	return append(variants, propName, optional, asString);
}

Recognizer::Phrase& Recognizer::Phrase::append(std::vector<PhraseElement::Variant> variants, std::wstring propName, bool optional, std::wstring asString)
{
	if (!phraseElements.empty())
		this->asString += L" ";
	auto& el = phraseElements.emplace_back(variants, propName, optional);
	if (!asString.empty()) {
		this->asString += L"<" + asString + L">";
	} else {
		this->asString += el.asString;
	}
	return *this;
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
	auto ruleID = newRuleId();
	rules.emplace(ruleID, std::move(Rule{ phrases, confidence, ruleID, persistenceMode}));
	return ruleID;
}

Recognizer::Rule& Recognizer::getRuleById(RuleID ruleID)
{
	return rules[ruleID];
}

RuleID Recognizer::newRuleId()
{
	static RuleID currRuleId = 0;
	currRuleId++;
	return currRuleId;
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

		for (auto& [_, rule] : rules) {

			statesBefore[&rule] = rule.state;

			if (rule.state != RuleState::Disabled) {
				rule.state = RuleState::Inactive;
				rule.sapiRuleState = SPRS_INACTIVE;
			}

			for (Phrase& phrase : rule.phrases) {
				auto& phraseElements = phrase.phraseElements;

				if (phraseElements.size() > 0) {

					std::function<void(std::vector<Phrase::PhraseElement>&, SPSTATEHANDLE)>parseElements;
					parseElements = [&](std::vector<Phrase::PhraseElement>& elements, SPSTATEHANDLE endState) {
						for (size_t i = 0; i < elements.size();) {
							auto& phraseElement = elements[i];
							SPSTATEHANDLE currState = phraseElement.state;
							SPSTATEHANDLE nextState = endState;
							if (++i < elements.size()) {
								recoGrammar->CreateNewState(currState, &elements[i].state);
								nextState = elements[i].state;
							}

							auto makeStateTransition = [&](Recognizer::Phrase::PhraseElement& element, SPSTATEHANDLE fromState, SPSTATEHANDLE toState) {

								SPPROPERTYINFO prop{};
								SPPROPERTYINFO* pProp = NULL;

								if (!element.propName.empty()) {
									pProp = &prop;
									prop.pszName = element.propName.c_str();
								}
								for (auto& variant : element.variants) {
									if (prop.pszName) {
										prop.pszValue = variant.name.empty() ? variant.asString.c_str() : variant.name.c_str();
									}
									if (variant.value.index() == IDX_STRING) {
										
										hr = recoGrammar->AddWordTransition(fromState, toState, std::get<std::wstring>(variant.value).c_str(), L" ", SPWT_LEXICAL, 1.0f, pProp);
										checkResult("Error in AddWordTransition", hr);
										if (phraseElement.optional) {
											hr = recoGrammar->AddWordTransition(fromState, toState, NULL, L" ", SPWT_LEXICAL, 1.0f, NULL);
										}
									} else {
										
										Phrase& phrase = *std::get<std::shared_ptr<Phrase>>(variant.value);
										if (!phrase.phraseElements.empty()) {
											hr = recoGrammar->GetRule(NULL, phrase.ruleID, SPRAF_Dynamic, TRUE, &phrase.phraseElements[0].state);
											hr = recoGrammar->AddRuleTransition(fromState, toState, phrase.phraseElements[0].state, 1, pProp);
											if (phraseElement.optional) {
												hr = recoGrammar->AddRuleTransition(fromState, toState, phrase.phraseElements[0].state, 1.0f, NULL);
											}
											parseElements(phrase.phraseElements, NULL);
										}
									}
								}
								
							};

							makeStateTransition(phraseElement, currState, nextState);
						}
					};

					hr = recoGrammar->GetRule(NULL, rule.ruleID, SPRAF_TopLevel | SPRAF_Active | SPRAF_Dynamic, TRUE, &phraseElements[0].state);
					checkResult("Error creating rule", hr);

					if (SUCCEEDED(hr)) {
						parseElements(phraseElements, NULL);
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

	auto PhraseType = lua.new_usertype<Phrase>("Phrase", sol::factories([] {return std::make_shared<Phrase>(); }));

	PhraseType["append"] = sol::overload(
		static_cast<Phrase&(Phrase::*)(Phrase::LuaVariantMap, std::wstring)>(&Phrase::append),
		static_cast<Phrase&(Phrase::*)(std::wstring)>(&Phrase::append),
		[](Phrase& phrase, sol::table t) -> Phrase& {
			Phrase::LuaVariantMap variantMap;
			if (t["variants"].get_type() == sol::type::table) {
				variantMap = t.get<Phrase::LuaVariantMap>("variants");
			} else {
				variantMap.push_back(t["variants"]);
			}
			if (t["propName"].get_type() == sol::type::string && !variantMap.empty()) {
				return phrase.append(
					variantMap,
					t.get<std::wstring>("propName"),
					t.get<std::optional<bool>>("optional").value_or(false),
					t.get<std::optional<std::wstring>>("asString").value_or(L"")
				);
			} else {
				return phrase.append(t.as<Phrase::LuaVariantMap>());
			}
		}
	);
	PhraseType["appendOptional"] = sol::overload(
		static_cast<Phrase & (Phrase::*)(Phrase::LuaVariantMap, std::wstring)>(&Phrase::appendOptional),
		static_cast<Phrase & (Phrase::*)(Phrase::VariantValue, std::wstring)>(&Phrase::appendOptional),
		static_cast<Phrase & (Phrase::*)(Phrase::LuaVariantMap)>(&Phrase::appendOptional),
		static_cast<Phrase & (Phrase::*)(Phrase::VariantValue)>(&Phrase::appendOptional)
	);
	PhraseType[sol::meta_function::to_string] = [](const Phrase& phrase) {return phrase.asString; };

	auto ResultType = lua.new_usertype<RecoResult>("RecoResult");
	ResultType["props"] = sol::readonly_property([](RecoResult& res) {return res.props; });
	ResultType["confidence"] = sol::readonly_property([](RecoResult& res) {return res.confidence; });
	ResultType["phrase"] = sol::readonly_property([](RecoResult& res) {return res.phrase; });
	using getPropRet = std::tuple<sol::optional<std::wstring>, sol::optional<PropTreeEntry&>>;
	ResultType["getProp"] = [](RecoResult& res, sol::variadic_args va) -> getPropRet {
		if (va.leftover_count() == 0)
			throw "Invalid argument";
		std::function<sol::optional<PropTreeEntry&>( PropTree&, size_t)> walk;
		walk = [&]( PropTree& tree, size_t keyIdx) -> sol::optional<PropTreeEntry&> {
			if (keyIdx > (va.leftover_count() - 1))
				return {};
			auto key = va.get<std::wstring>(keyIdx);
			auto it = tree.find(key);
			if (it == tree.end()) return {};
			if (keyIdx + 1 > (va.leftover_count() - 1))
				return it->second;
			return walk(it->second.children, keyIdx + 1);
		};
		sol::optional<PropTreeEntry&> ret{};
		if (va[0].is<PropTreeEntry>()) {
			ret = walk(va.get<PropTreeEntry>(0).children, 1);
		} else {
			ret = walk(res.props, 0);
		}
		if (ret) {
			auto& val = ret.value();
			return std::make_tuple(val.value, ret);
		}
		return getPropRet();
	};

	auto PropTreeEntryType = lua.new_usertype<PropTreeEntry>("RecoResultPropTreeEntry");
	PropTreeEntryType["value"] = sol::readonly_property([](PropTreeEntry& entry) {return entry.value; });
	PropTreeEntryType["children"] = sol::readonly_property([](PropTreeEntry& entry) {return entry.children; });
	PropTreeEntryType[sol::meta_function::to_string] = [](PropTreeEntry& entry) {return entry.value; };
	
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

void walkPropertyTree(const SPPHRASEPROPERTY* prop, PropTree& propTree) {
	if (!prop) return;
	do {
		auto it = propTree.emplace(prop->pszName, PropTreeEntry{ prop->pszValue });
		walkPropertyTree(prop->pFirstChild, it.first->second.children);
	} while (prop = prop->pNextSibling);
};

RecoResult Recognizer::getResult()
{
	CSpEvent event;
	if (event.GetFrom(recoContext) == S_OK && event.eEventId == SPEI_RECOGNITION) {
		HRESULT hr;
		CSpDynamicString dstrText;
		CSpPhrasePtr spphrase;
		auto recoResult = event.RecoResult();
		hr = recoResult->GetPhrase(&spphrase);
		if (SUCCEEDED(hr))
			hr = recoResult->GetText(SP_GETWHOLEPHRASE, SP_GETWHOLEPHRASE, TRUE, &dstrText, NULL);
		if (SUCCEEDED(hr)) {
			RuleID ruleID = spphrase->Rule.ulId;
			float confidence = spphrase->Rule.SREngineConfidence;
			std::wstring phrase = dstrText.Copy();
			std::lock_guard<std::recursive_mutex> lock(mtx);
			const Rule& rule = getRuleById(ruleID);
			if (rule.state != RuleState::Ignore && confidence >= rule.confidence) {
				PropTree propTree;
				walkPropertyTree(spphrase->pProperties, propTree);
				return RecoResult{ std::move(phrase), confidence, std::move(propTree), ruleID };
			}
		}
	}
	return {};
}