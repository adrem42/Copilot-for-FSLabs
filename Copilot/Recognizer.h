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
	std::string phrase;
	float confidence;
	RuleID ruleID;
};

class Recognizer {
public:
	enum class RulePersistenceMode { NonPersistent, Persistent, Ignore };
private:
	enum class RuleState { Active, Inactive, Ignore, Disabled };
	struct Rule {
		std::vector<std::string> phrases;
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
	RuleID addRule(std::vector<std::string> phrases, float confidence, RulePersistenceMode persistenceMode);
	void ignoreRule(RuleID ruleID);
	void activateRule(RuleID ruleID);
	void deactivateRule(RuleID ruleID);
	void disableRule(RuleID ruleID);
	sol::as_table_t<std::vector<std::string>> getPhrases(RuleID ruleID, bool dummy);
	void addPhrases(std::vector<std::string> phrases, RuleID ruleID, bool dummy);
	void removePhrases(std::vector<std::string> phrases, RuleID ruleID, bool dummy);
	void removeAllPhrases(RuleID ruleID, bool dummy);
	void setConfidence(float confidence, RuleID ruleID);
	void setRulePersistence(RulePersistenceMode persistenceMode, RuleID ruleID);
	void resetGrammar();
	void afterRecoEvent(RuleID ruleID);
	RecoResult getResult();
};