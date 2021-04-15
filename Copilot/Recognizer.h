/////
// 
// @module VoiceCommand

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
#include <unordered_set>

using RuleID = DWORD;
struct PropTreeEntry;
using PropTree = std::unordered_map<std::wstring, PropTreeEntry>;

struct PropTreeEntry {
	std::wstring value;
	PropTree children;
};

/*** 
* The payload of a VoiceCommand event
 * @usage
	*  
	* local helloGoodbye = VoiceCommand:new {
	*   phrase = Phrase.new()
	*     :append {
	*       propName = "what",
	*       variants = {
	*         {
 	*           propVal = "greeting",
 	*           variant = Phrase.new():append"hello":appendOptional({"there", "again"}, "optProp")
 	*         },
 	*         "goodbye"
	*       },
	*     }
	*     :appendOptional"friend",
	*   persistent = true,
	*   action = function(_, res)
	*     print(res:getProp("what")) -- "greeting" or "goodbye"
	*     print(res:getProp("what", "optProp"))  -- "there", "again" or nil
	*   end
	* }
	* 
	* copilot.callOnce(function()
	*   helloGoodbye:activate()
	* end)
* @type RecoResult
* 
*/
struct RecoResult {
	/***
	* The phrase that was spoken
	* @string phrase 
	*/
	std::wstring phrase;
	/***
	* Recognition engine confidence
	* @number confidence 
	*/
	float confidence;
	/***
	* The properties and their values that were defined when constructing the Phrase.
	* If a value is optional, it will not have an entry in the tree.
	* @field props Property tree.
	* @string props.value 
	* @field props.children Child properties. A property tree has children when you have a Phrase within a Phrase
	*/
	PropTree props;
	/***
	* @function getProp Retrieves a named property.
	* 
	* @param ... The tree path to the property
	* 
	* @treturn string The value field of the property or nil
	* @return The property or nil
	*/
	RuleID ruleID;
};

class Recognizer {
	friend class Phrase;
private:
	RuleID newRuleId();
public:
	enum class RulePersistenceMode { NonPersistent, Persistent, Ignore };
	/***
	* Class that allows you to create complex phrases with optional elements,
	* elements with multiple variants and named properties.
	* @type Phrase
	*/
	struct Phrase : public std::enable_shared_from_this<Phrase> {
		friend class Recognizer;
		ISpRecoGrammar* const recoGrammar;
		Recognizer* const recognizer;
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

		SPSTATEHANDLE initialState;
		const RuleID ruleID;

		Phrase(Recognizer* recognizer, ISpRecoGrammar* recoGrammar);

		void resetGrammar();

		/***
		* Constructor
		* @static
		* @function new
		*/
		
		std::vector<PhraseElement> phraseElements;
		std::wstring asString;
		std::string name;
		std::shared_ptr<Phrase> setName(const std::string&);

		/***
		* Appends an element
		* @function append
		* @param element A string or Phrase
		* @string[opt] propName Name of the property
		* @return self
		*/
		std::shared_ptr<Phrase> append(VariantValue);
		std::shared_ptr<Phrase> append(VariantValue, std::wstring);

		/***
		* Appends an element. 
		* @function append
		* @tparam table args
		* @string args.propName Name of the property
		* @bool[opt=false] args.optional Whether this element is optional
		* @param args.variants Either a single string or Phrase or an array of variants where a variant can be:
		* <ul>
		* <li>A table with a `propVal` and a `variant` field that is either a string or Phrase</li>
		* <li>A string or a Phrase</li>
		* </ul>
		* @return self
		* @usage 
		* Phrase.new():append {
		*    propName = "what",
		*    variants = {
		*      "goodbye", -- same as {propVal = "goodbye", variant = "goodbye"}
		*      {propVal = "greeting", variant = "hi"},
		*      {
		*        propVal = "greeting",
		*        variant = Phrase.new():append"good day":appendOptional("sir", "extraPolite")  
		*      },
		*      {propVal = "greeting", variant = "hello"}
		*    },
		*  }
		*/

		/***
		* Appends an element with multiple variants.
		* @function append
		* @tparam table variants An array of variants where a variant can be:
		* <ul>
		* <li>A table with a `propVal` and a `variant` field that is either a string or Phrase</li>
		* <li>A string or a Phrase</li>
		* </ul>
		* @string[opt] propName Property name.
		* @return self
		* @usage
		* Phrase.new():append({"hello", "goodbye"}, "what")
		*/
		std::shared_ptr<Phrase> append(LuaVariantMap);
		std::shared_ptr<Phrase> append(LuaVariantMap, std::wstring);
		
		/***
		* Appends an optional element.
		* @function appendOptional
		* @param element A string or a Phrase
		* @string[opt] propName Property name.
		* @return self
		*/
		std::shared_ptr<Phrase> appendOptional(VariantValue);
		std::shared_ptr<Phrase> appendOptional(VariantValue, std::wstring);

		/***
		* Appends an optional element with multiple variants.
		* @function appendOptional
		* @param variants See above
		* @string[opt] propName Property name.
		* @return self
		*/
		std::shared_ptr<Phrase> appendOptional(LuaVariantMap);
		std::shared_ptr<Phrase> appendOptional(LuaVariantMap, std::wstring);

		/***
		* Replaces an element with the given propName with another element
		* @string propName
		* @return self
		*/
		std::shared_ptr<Phrase> replace(std::wstring propName, VariantValue);

	private:

		std::shared_ptr<Phrase> append(LuaVariantMap, std::wstring, bool, std::wstring = L"");
		std::shared_ptr<Phrase> append(std::vector<PhraseElement::Variant>, std::wstring, bool, std::wstring = L"");
	};
private:
	std::unordered_set<std::shared_ptr<Phrase>> dirtyPhrases;
	bool hasDirtyRules = false;
	void markPhraseDirty(std::shared_ptr<Phrase>);
	enum class RuleState { Active, Inactive, Ignore, Disabled };
	struct Rule {
		std::vector<std::shared_ptr<Phrase>> phrases;
		float confidence;
		RuleID ruleID;
		RulePersistenceMode persistenceMode;
		RuleState state = RuleState::Inactive;
		RuleID dummyRuleID;
		SPRULESTATE sapiRuleState = SPRS_INACTIVE;
		SPSTATEHANDLE sapiState = 0;
	};
	RuleID currRuleId = 0;
	Rule& getRuleById(RuleID ruleID);
	void changeRuleState(Rule& rule, RuleState newRuleState, SPRULESTATE spRuleState, std::string&& logMsg, std::string&& dummyLogMsg);
	CComPtr<ISpRecognizer> recognizer;
	CComPtr<ISpRecoGrammar> recoGrammar;
	CComPtr<ISpRecoContext> recoContext;
	CComPtr<ISpAudio> audio;
	void logRuleStatus(std::string& prefix, const Rule& rule);
	std::unordered_map<RuleID, Rule> rules;
	std::recursive_mutex mtx;
public:
	Recognizer();
	~Recognizer();
	void registerCallback(ISpNotifyCallback* callback);
	RuleID addRule(std::vector<std::shared_ptr<Phrase>> phrases, float confidence, RulePersistenceMode persistenceMode);
	void ignoreRule(RuleID ruleID);
	void activateRule(RuleID ruleID);
	void deactivateRule(RuleID ruleID);
	void disableRule(RuleID ruleID);
	RuleState getRuleState(RuleID ruleID);
	sol::as_table_t<std::vector<std::shared_ptr<Phrase>>> getPhrases(RuleID ruleID, bool dummy);
	void addPhrases(std::vector<std::shared_ptr<Phrase>> phrases, RuleID ruleID, bool dummy);
	//void removePhrases(std::vector<Phrase> phrases, RuleID ruleID, bool dummy);
	void removeAllPhrases(RuleID ruleID, bool dummy);
	void setConfidence(float confidence, RuleID ruleID);
	void setRulePersistence(RulePersistenceMode persistenceMode, RuleID ruleID);
	void resetGrammar();
	void afterRecoEvent(RuleID ruleID);
	void makeLuaBindings(sol::state_view&);
	RecoResult getResult();
};