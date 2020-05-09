#pragma once
#pragma warning(disable : 4996)
#include <sphelper.h>
#include <mutex>
#include <vector>
#include <string>
#include <memory>
#include <optional>
#include <atomic>
#include <sol/sol.hpp>

struct RecoResult {
	std::string phrase;
	float confidence;
	DWORD ruleID;
};

class Recognizer {
private:
	enum RuleState { Active, Inactive, Ignore };
	struct Rule {
		std::vector<std::string> phrases;
		float confidence;
		DWORD ruleID;
		RuleState state = Inactive;
	};
	CComPtr<ISpRecognizer> recognizer;
	CComPtr<ISpRecoGrammar> recoGrammar;
	CComPtr<ISpRecoContext> recoContext;
	CComPtr<ISpAudio> audio;
	DWORD ruleID = 0;
	std::vector<Rule> rules;
	std::mutex mtx;
public:
	Recognizer();
	~Recognizer();
	DWORD addRule(const std::vector<std::string> phrases, float confidence);
	void ignoreRule(DWORD ruleID);
	void activateRule(DWORD ruleID);
	void deactivateRule(DWORD ruleID);
	sol::as_table_t<std::vector<std::string>> getPhrases(DWORD ruleID);
	void addPhrase(const std::string& phrase, DWORD ruleID);
	void removePhrase(const std::string& phrase, DWORD ruleID);
	void removeAllPhrases(DWORD ruleID);
	void setConfidence(float confidence, DWORD ruleID);
	void resetGrammar();
	std::optional<RecoResult> getResult();
};
