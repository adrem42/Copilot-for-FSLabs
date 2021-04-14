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
	*     -- without getProp, you would have to type this:
	*     local optProp = res.props.what.children.optProp
	*     if optProp then
	*       print(optProp.value)
	*     end
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
	RuleID ruleID;
	static RuleID newRuleId();
public:
	enum class RulePersistenceMode { NonPersistent, Persistent, Ignore };
	/***
	* Class that allows you to create complex phrases with optional elements,
	* elements with multiple variants and named properties.
	* @type Phrase
	*/
	struct Phrase {
		friend class Recognizer;
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

		/***
		* Constructor
		* @static
		* @function new
		*/

		RuleID ruleID = Recognizer::newRuleId();
		std::vector<PhraseElement> phraseElements;
		std::wstring asString;
		std::string name;
		Phrase& setName(const std::string&);

		/***
		* Appends a simple string 
		* @function append
		* @string str 
		* @return self
		*/
		Phrase& append(std::wstring);

		/***
		* Appends a named element with multiple variants. 
		* Multiple variants of a property can be aliased by the same name (like "greeting" in the example below).
		* @function append
		* @tparam table args
		* @string args.propName Name of the property
		* @bool[opt=false] args.optional Whether this element is optional
		* @tparam table args.variants An array of variants where a variant can be:
		* <ul>
		* <li>A table with a `propVal` and a `variant` field that is either a string or Phrase</li>
		* <li>A string or a Phrase</li>
		* </ul>
		* @return self
		* @usage 
		* Phrase.new()
		*  :append {
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
		* Appends a named element with multiple variants.
		* Multiple variants of a property can be aliased by the same name.
		* @function append
		* @tparam table variants An array of variants where a variant can be:
		* <ul>
		* <li>A table with a `propVal` and a `variant` field that is either a string or Phrase</li>
		* <li>A string or a Phrase</li>
		* </ul>
		* @string propName name of the property
		* @return self
		* @usage
		* Phrase.new():append({"hello", "goodbye"}, "what")
		*/
		Phrase& append(LuaVariantMap, std::wstring);
		
		/***
		* Appends an element with multiple variants.
		* @function append
		* @param multiElement See above
		* @return self
		*/
		Phrase& append(LuaVariantMap);

		/***
		* Appends an optional element.
		* @function appendOptional
		* @param element A string or a Phrase
		* @return self
		*/
		Phrase& appendOptional(VariantValue);

		/***
		* Appends an optional named element. 
		* @function appendOptional
		* @param element A string or a Phrase
		* @string name Name of the property
		* @return self
		*/
		Phrase& appendOptional(VariantValue, std::wstring);

		/***
		* Appends an optional element with multiple variants.
		* @function appendOptional
		* @param multiElement See above
		* @return self
		*/
		Phrase& appendOptional(LuaVariantMap);

		/***
		* Appends an optional named element with multiple variants.
		* @function appendOptional
		* @param multiElement See above
		* @string name
		* @return self
		*/
		Phrase& appendOptional(LuaVariantMap, std::wstring);

	private:

		Phrase& append(LuaVariantMap, std::wstring, bool, std::wstring = L"");
		Phrase& append(std::vector<PhraseElement::Variant>, std::wstring, bool, std::wstring = L"");
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