#pragma once
#pragma warning(disable : 4996)
#include <sphelper.h>
#include <mutex>
#include <vector>
#include <string>
#include <memory>
#include <atomic>
#include <sol/sol.hpp>
#include <unordered_map>

using RuleID = DWORD;

struct RecoResult {
	std::wstring phrase;
	float confidence;
	std::unordered_map<std::wstring, std::wstring> props;
	RuleID ruleID;
};

class Recognizer {
public:
	enum class RulePersistenceMode { NonPersistent, Persistent, Ignore };
	struct Phrase {
		using VariantValue = std::variant<std::wstring, std::shared_ptr<Phrase>>;
		using LuaVariantMap = std::vector<sol::object>;
		struct PhraseElement {
			struct Variant { 
				VariantValue value; 
				std::wstring name; 
				std::wstring asString;
				Variant() = delete;
				Variant(VariantValue val, std::wstring name = L"");
			};
			std::vector<Variant> variants;
			std::wstring propName;
			bool optional;
			SPSTATEHANDLE state = 0;
			std::wstring asString;
			PhraseElement(std::vector<Variant> variants, std::wstring propName, bool optional);
		};

		std::vector<PhraseElement> phraseElements;
		std::wstring asString;
		std::string name;
		Phrase& setName(const std::string&);

		Phrase& append(std::wstring);

		Phrase& appendOptional(VariantValue);
		Phrase& appendOptional(VariantValue, std::wstring);
		
		Phrase& append(LuaVariantMap);
		Phrase& append(LuaVariantMap, std::wstring);

		Phrase& appendOptional(LuaVariantMap);
		Phrase& appendOptional(LuaVariantMap, std::wstring);

	private:

		Phrase& append(LuaVariantMap, std::wstring, bool);
		Phrase& append(std::vector<PhraseElement::Variant>, std::wstring, bool);
	};
private:
	enum class RuleState { Active, Inactive, Ignore, Disabled };
	struct Rule {
		std::vector<Phrase> phrases;
		float confidence;
		RuleID ruleID;
		RulePersistenceMode persistenceMode;
		RuleState state = RuleState::Inactive;
		RuleID dummyRuleID;
		SPRULESTATE sapiRuleState = SPRS_INACTIVE;
	};
	Rule& getRuleById(RuleID ruleID);
	void changeRuleState(Rule& rule, RuleState newRuleState, SPRULESTATE spRuleState, std::string&& logMsg, std::string&& dummyLogMsg);
	CComPtr<ISpRecognizer> recognizer;
	CComPtr<ISpRecoGrammar> recoGrammar;
	CComPtr<ISpRecoContext> recoContext;
	CComPtr<ISpAudio> audio;
	RuleID CurrRuleId = 0;
	static const size_t DEAD_RULE_CLEANUP_THRESHOLD = 50;
	void logRuleStatus(std::string& prefix, const Rule& rule);
	std::unordered_map<RuleID, Rule> rules;
	std::recursive_mutex mtx;
public:
	Recognizer();
	~Recognizer();
	void registerCallback(ISpNotifyCallback* callback);
	RuleID addRule(std::vector<Phrase> phrases, float confidence, RulePersistenceMode persistenceMode);
	void ignoreRule(RuleID ruleID);
	void activateRule(RuleID ruleID);
	void deactivateRule(RuleID ruleID);
	void disableRule(RuleID ruleID);
	RuleState getRuleState(RuleID ruleID);
	sol::as_table_t<std::vector<Phrase>> getPhrases(RuleID ruleID, bool dummy);
	void addPhrases(std::vector<Phrase> phrases, RuleID ruleID, bool dummy);
	//void removePhrases(std::vector<Phrase> phrases, RuleID ruleID, bool dummy);
	void removeAllPhrases(RuleID ruleID, bool dummy);
	void setConfidence(float confidence, RuleID ruleID);
	void setRulePersistence(RulePersistenceMode persistenceMode, RuleID ruleID);
	void resetGrammar();
	void afterRecoEvent(RuleID ruleID);
	static void makeLuaBindings(sol::state_view&);
	RecoResult getResult();
};