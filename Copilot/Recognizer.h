#pragma once
#pragma warning(disable : 4996)
#include <sphelper.h>
#include <mutex>
#include <vector>
#include <string>
#include <memory>
#include <optional>
#include <atomic>

struct RecoResult {
	std::string phrase;
	float confidence;
	DWORD ruleID;
};

class Recognizer {
private:
	struct Rule {
		std::vector<std::string> phrases;
		float confidence;
		DWORD ruleID;
		bool ignore = false;
	};
	CComPtr<ISpRecognizer> recognizer;
	CComPtr<ISpRecoGrammar> recoGrammar;
	CComPtr<ISpRecoContext> recoContext;
	CComPtr<ISpAudio> audio;
	DWORD ruleID = 0;
	std::vector<Rule> rules;
	std::mutex mtx;
public:
	bool init();
	~Recognizer();
	DWORD addRule(std::vector<std::string> phrases, float confidence);
	void ignoreRule(DWORD ruleID);
	void activateRule(DWORD ruleID);
	void deactivateRule(DWORD ruleID);
	void resetGrammar();
	std::optional<RecoResult> getResult();
};
