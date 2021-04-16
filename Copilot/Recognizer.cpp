#include "Recognizer.h"
#include "Copilot.h"
#include <sstream>
#include <map>
#include <vector>

const int IDX_STRING = 0;

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
		
		for (size_t i = 0; i < this->variants.size(); ++i) {
			asString += L"{";
			asString += this->variants[i].asString;
			asString += L"}";
			if (i < this->variants.size() - 1) {
				asString += L"+";
			}
		}
	}
	if (optional)
		asString += L"]";
}

Recognizer::Phrase::Phrase(Recognizer* recognizer, ISpRecoGrammar* recoGrammar, std::vector<PhraseElement> elements, std::wstring asString)
	:recoGrammar(recoGrammar), recognizer(recognizer), ruleID(recognizer->newRuleId()), phraseElements(elements), asString(asString)
{
	checkResult("Error in GetRule", recoGrammar->GetRule(NULL, ruleID, SPRAF_Dynamic, TRUE, &initialState));
}

void Recognizer::Phrase::resetGrammar()
{
	if (phraseElements.empty())
		return;

	recognizer->markGrammarDirty();

	recoGrammar->ClearRule(initialState);
	phraseElements[0].state = initialState;

	for (size_t i = 0; i < phraseElements.size();) {

		auto& phraseElement = phraseElements[i];
		SPSTATEHANDLE fromState = phraseElement.state;
		SPSTATEHANDLE toState = NULL;

		if (++i < phraseElements.size()) {
			recoGrammar->CreateNewState(fromState, &phraseElements[i].state);
			toState = phraseElements[i].state;
		}

		HRESULT hr;

		SPPROPERTYINFO prop{};
		SPPROPERTYINFO* pProp = NULL;

		if (!phraseElement.propName.empty()) {
			pProp = &prop;
			pProp->pszName = phraseElement.propName.c_str();
		}
		if (phraseElement.optional) {
			hr = recoGrammar->AddWordTransition(fromState, toState, NULL, NULL, SPWT_LEXICAL, 1, NULL);
		}
		for (auto& variant : phraseElement.variants) {
			if (pProp) {
				pProp->pszValue = variant.name.empty() ? variant.asString.c_str() : variant.name.c_str();
			}
			if (variant.value.index() == IDX_STRING) {
				hr = recoGrammar->AddWordTransition(fromState, toState, std::get<std::wstring>(variant.value).c_str(), L" ", SPWT_LEXICAL, 1, pProp);
				checkResult("Error in AddWordTransition", hr);
			} else {
				Phrase& phrase = *std::get<std::shared_ptr<Phrase>>(variant.value);
				hr = recoGrammar->AddRuleTransition(fromState, toState, phrase.initialState, 1, pProp);
			}
		}
	}
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::append(Phrase::VariantValue phraseElement)
{
	return append(std::vector<Phrase::PhraseElement::Variant>{std::move(Phrase::PhraseElement::Variant(phraseElement))}, L"", false);
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::append(Phrase::VariantValue phraseElement, std::wstring propName)
{
	return append(std::vector<Phrase::PhraseElement::Variant>{std::move(Phrase::PhraseElement::Variant(phraseElement))}, propName, false);
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::appendOptional(Phrase::VariantValue phraseElement)
{
	return append(std::vector<Phrase::PhraseElement::Variant>{std::move(Phrase::PhraseElement::Variant(phraseElement))}, L"", true);
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::appendOptional(Phrase::VariantValue phraseElement, std::wstring propName)
{
	return append(std::vector<Phrase::PhraseElement::Variant>{std::move(Phrase::PhraseElement::Variant(phraseElement))}, propName, true);
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::append(LuaVariantMap phraseElement)
{
	return append(phraseElement, L"");
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::append(LuaVariantMap phraseElement, std::wstring propName)
{
	return append(phraseElement, propName, false);
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::appendOptional(LuaVariantMap phraseElement)
{
	return append(phraseElement, L"", true);
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::appendOptional(LuaVariantMap phraseElement, std::wstring propName)
{
	return append(phraseElement, propName, true);
}

std::shared_ptr<Recognizer::Phrase> Recognizer::PhraseBuilder::build()
{
	return _build(this->asString);
}

std::shared_ptr<Recognizer::Phrase> Recognizer::PhraseBuilder::build(std::wstring asString)
{
	return _build(L"<" + asString + L">");
}

std::shared_ptr<Recognizer::Phrase> Recognizer::PhraseBuilder::_build(std::wstring asString)
{
	auto phrase = std::make_shared<Recognizer::Phrase>(recognizer, recoGrammar, phraseElements, asString);
	phrase->resetGrammar();
	return phrase;
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::append(LuaVariantMap phraseElement, std::wstring propName, bool optional, std::wstring asString)
{
	std::vector<Phrase::PhraseElement::Variant> variants;

	for (auto& element : phraseElement) {
		std::wstring name;
		Phrase::VariantValue varValue;
		if (element.get_type() == sol::type::table) {
			sol::table t = element;
			if (t["propVal"].get_type() == sol::type::string)
				name = t.get<std::wstring>("propVal");
			varValue = t.get<Phrase::VariantValue>("variant");
		} else {
			varValue = element.as<Phrase::VariantValue>();
		}
		variants.emplace_back(varValue, name);
	}

	return append(variants, propName, optional, asString);
}

Recognizer::PhraseBuilder& Recognizer::PhraseBuilder::append(std::vector<Phrase::PhraseElement::Variant> variants, std::wstring propName, bool optional, std::wstring asString)
{
	if (!phraseElements.empty())
		this->asString += L" ";
	auto& el = phraseElements.emplace_back(variants, propName, optional);
	if (!asString.empty()) 
		el.asString = L"<" + asString + L">";
	this->asString += el.asString;
	return *this;
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

	HRESULT hr = recoGrammar->ResetGrammar(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US));
	if (FAILED(hr)) {
		throwOnBadResult("Error in ResetGrammar", recoGrammar->ResetGrammar(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_UK)));
	}
}

Recognizer::~Recognizer()
{
	CoUninitialize();
}

void Recognizer::registerCallback(ISpNotifyCallback* callback)
{
	throwOnBadResult(
		"Error setting up notification callback",
		recoContext->SetNotifyCallbackInterface(callback, 0, 0)
	);
}

RuleID Recognizer::addRule(std::vector<std::shared_ptr<Phrase>> phrases, float confidence, RulePersistenceMode persistenceMode)
{
	std::lock_guard<std::recursive_mutex> lock(mtx);
	auto ruleID = newRuleId();
	auto it = rules.emplace(ruleID, std::move(Rule{ phrases, confidence, ruleID, persistenceMode}));
	HRESULT hr;
	if (!phrases.empty()) {
		hr = recoGrammar->GetRule(NULL, ruleID, SPRAF_TopLevel | SPRAF_Dynamic, TRUE, &it.first->second.sapiState);
		checkResult("Error in GetRule", hr);
	}
	for (auto& phrase : phrases) {
		recoGrammar->AddRuleTransition(it.first->second.sapiState, NULL, phrase->initialState, 1, 0);
	}
	markGrammarDirty();
	return ruleID;
}


void Recognizer::markGrammarDirty()
{
	grammarIsDirty = true;
}

Recognizer::Rule& Recognizer::getRuleById(RuleID ruleID)
{
	return rules[ruleID];
}

RuleID Recognizer::newRuleId()
{
	currRuleId++;
	return currRuleId;
}

void Recognizer::logRuleStatus(std::string& prefix, const Rule& rule)
{
	copilot::logger->debug(L"{} top level rule {} ({})", std::wstring(prefix.begin(), prefix.end()), rule.ruleID,
						   rule.phrases.empty() ? L"rule has no phrase variants" : L"phrase #1: '" + rule.phrases[0]->asString + L"'");
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

sol::as_table_t<std::vector<std::shared_ptr<Recognizer::Phrase>>> Recognizer::getPhrases(RuleID ruleID, bool dummy = false)
{
	Rule& rule = getRuleById(ruleID);
	if (dummy) {
		if (rule.dummyRuleID) return getRuleById(rule.dummyRuleID).phrases;
		return {};
	}
	return getRuleById(ruleID).phrases;
}

void Recognizer::addPhrases(std::vector<std::shared_ptr<Recognizer::Phrase>> phrases, RuleID ruleID, bool dummy = false)
{
	markGrammarDirty();
	auto add = [&](Rule& rule) {
		if (!rule.sapiState) {
			HRESULT hr = recoGrammar->GetRule(NULL, rule.ruleID, SPRAF_TopLevel | SPRAF_Dynamic, TRUE, &rule.sapiState);
		}
		auto it = rule.phrases.insert(rule.phrases.end(), phrases.begin(), phrases.end());
		for (auto& phrase : phrases) {
			recoGrammar->AddRuleTransition(rule.sapiState, NULL, phrase->initialState, 1, 0);
		}
	};

	auto& rule = getRuleById(ruleID);

	if (dummy) {
		RuleID dummyRuleID = rule.dummyRuleID;
		if (!dummyRuleID) {
			rule.dummyRuleID = addRule(phrases, 1.0, RulePersistenceMode::Ignore);
		} else {
			add(getRuleById(dummyRuleID));
		}	
	} else {
		add(rule);
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
	if (rule.sapiState) {
		recoGrammar->ClearRule(rule.sapiState);
		rule.sapiState = 0;
	}
	markGrammarDirty();
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
	if (!grammarIsDirty) return;
	grammarIsDirty = false;
	copilot::logger->debug("Updating grammar");
	HRESULT hr;
	hr = recognizer->SetRecoState(SPRST_INACTIVE);
	checkResult("Error deactivating reco state", hr);
	hr = recoContext->Pause(NULL);
	checkResult("Error pausing reco context", hr);
	hr = recognizer->SetRecoState(SPRST_ACTIVE);
	checkResult("Error reactivating reco state", hr);
	hr = recoGrammar->Commit(NULL);
	checkResult("Error while commiting grammar", hr);
	hr = recoContext->Resume(NULL);
	checkResult("Error while resuming reco context", hr);
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

	

	auto PhraseBuilderType = lua.new_usertype<PhraseBuilder>(
		"PhraseBuilder",
		sol::factories([&] {return PhraseBuilder(this, recoGrammar.p);})
	);

	PhraseBuilderType["append"] = sol::overload(
		static_cast<PhraseBuilder& (PhraseBuilder::*)(PhraseBuilder::LuaVariantMap, std::wstring)>(&PhraseBuilder::append),
		static_cast<PhraseBuilder& (PhraseBuilder::*)(Phrase::VariantValue)>(&PhraseBuilder::append),
		static_cast<PhraseBuilder& (PhraseBuilder::*)(Phrase::VariantValue, std::wstring)>(&PhraseBuilder::append),
		[](PhraseBuilder& builder, sol::table t) -> PhraseBuilder& {
			PhraseBuilder::LuaVariantMap variantMap;
			if (t["variants"].get_type() == sol::type::table) {
				variantMap = t.get<PhraseBuilder::LuaVariantMap>("variants");
			} else {
				variantMap.push_back(t["variants"]);
			}
			if (t["propName"].get_type() == sol::type::string && !variantMap.empty()) {
				builder.append(
					variantMap,
					t.get<std::wstring>("propName"),
					t.get<std::optional<bool>>("optional").value_or(false),
					t.get<std::optional<std::wstring>>("asString").value_or(L"")
				);
			} else {
				builder.append(t.as<PhraseBuilder::LuaVariantMap>());
			}
			return builder;
		}
	);
	PhraseBuilderType["appendOptional"] = sol::overload(
		static_cast<PhraseBuilder&(PhraseBuilder::*)(PhraseBuilder::LuaVariantMap, std::wstring)>(&PhraseBuilder::appendOptional),
		static_cast<PhraseBuilder&(PhraseBuilder::*)(Phrase::VariantValue, std::wstring)>(&PhraseBuilder::appendOptional),
		static_cast<PhraseBuilder&(PhraseBuilder::*)(PhraseBuilder::LuaVariantMap)>(&PhraseBuilder::appendOptional),
		static_cast<PhraseBuilder&(PhraseBuilder::*)(Phrase::VariantValue)>(&PhraseBuilder::appendOptional)
	);

	PhraseBuilderType["build"] = sol::overload(
		static_cast<std::shared_ptr<Recognizer::Phrase>(PhraseBuilder::*)(std::wstring)>(&PhraseBuilder::build),
		static_cast<std::shared_ptr<Recognizer::Phrase>(PhraseBuilder::*)()>(&PhraseBuilder::build)
	);

	auto PhraseType = lua.new_usertype<Phrase>("Phrase");

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