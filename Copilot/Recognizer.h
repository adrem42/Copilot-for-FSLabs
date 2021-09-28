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
#include <spdlog/logger.h>

using RuleID = DWORD;
struct RecoProp;
using PropTree = std::unordered_map<std::wstring, RecoProp>;

/***
* @type RecoProp
*/
struct RecoProp {
	/*** @string value */
	std::wstring value;
	/*undocumented because pretty much useless*/
	float confidence; 
	/*** Table in the `propName=RecoProp` format 
	*@tfield table children */
	PropTree children;
};

/*** 
* The payload of a VoiceCommand event
 * @usage
	*  
	* local helloGoodbye = VoiceCommand:new {
	*   phrase = PhraseBuilder.new()
	*     :append {
	*       propName = "what",
	*       choices = {
	*         {
 	*           propVal = "greeting",
 	*           choice = PhraseBuilder.new()
	*             :append "hello"
	*             :appendOptional({"there", "again"}, "optProp")
	*             :build()
 	*         },
 	*         "goodbye"
	*       },
	*     }
	*     :appendOptional "friend"
	*     :build(),
	*   persistent = true,
	*   action = function(_, recoResult)
	*     print(recoResult:getProp("what")) -- "greeting" or "goodbye"
	*     print(recoResult:getProp("what", "optProp"))  -- "there", "again" or nil
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
	* If a property-bound phrase element is optional and the element is absent in the spoken phrase, `props.propName` will be nil.
	* @tfield table props Table in the `propName=RecoProp` format.
	*/
	PropTree props;
	/***
	* Convenience method for retrieving property values.
	* @function getProp 
	* @param ... path Strings denoting the tree path to the wanted property. If the first argument is a RecoProp, the search will be started there.
	* @treturn[1] string The value field of the RecoProp
	* @return[1] RecoProp 
	* @return[2] nil
	* @return[2] nil
	*/
	RuleID ruleID;
};

class Recognizer : public std::enable_shared_from_this<Recognizer> {
	friend class Phrase;
private:
	RuleID newRuleId();
public:
	enum class RulePersistenceMode { NonPersistent, Persistent, Ignore };

	/***
	 * Allows you to create complex phrases containing multiple-choice and optional elements that can be bound to named properties.
	 * 
	 * A Phrase can be used on its own and as a building block for composing other Phrases. A Phrase can have multiple parent Phrases as well as multiple child Phrases.
	 * 
	 * Use the PhraseBuilder class to create a Phrase (which itself is immutable).
	 * @type Phrase
	 */

	/***
	* @field .    
	*/

	class PhraseBuilder;
	/***
	* Builds a Phrase
	* @type PhraseBuilder
	*/
	struct Phrase {

		friend class Recognizer;
		friend class PhraseBuilder;
		CComPtr<ISpRecoGrammar> const recoGrammar;
		Recognizer* const recognizer;
		using ChoiceValue = std::variant<std::wstring, std::shared_ptr<Phrase>>;
		
		struct PhraseElement {
			struct Choice { 
				ChoiceValue value; 
				std::wstring name; 
				std::wstring asString;
				Choice() = delete;
				Choice(ChoiceValue val, std::wstring name = L"");
			};
			std::vector<Choice> choices;
			std::wstring propName;
			bool optional;
			SPSTATEHANDLE state = 0;
			std::wstring asString;
			PhraseElement(std::vector<Choice>, std::wstring, bool);
		};

		SPSTATEHANDLE initialState;
		const RuleID ruleID;

		Phrase(Recognizer*, CComPtr<ISpRecoGrammar>, std::vector<PhraseElement>, std::wstring);

		void resetGrammar();

		/***
		* Constructor
		* @static
		* @function new
		*/
		
		std::vector<PhraseElement> phraseElements;
		const std::wstring asString;

		~Phrase();

	};

	struct PhraseBuilder { 
		friend class Recognizer;
		Recognizer* const recognizer; 
		ISpRecoGrammar* const recoGrammar;
		std::vector<Phrase::PhraseElement> phraseElements;
		std::wstring asString;
		using LuaChoiceMap = std::vector<sol::object>;

		PhraseBuilder(Recognizer* recognizer, ISpRecoGrammar* recoGrammar)
			:recognizer(recognizer), recoGrammar(recoGrammar) { }

		/***
		* Appends an element
		* @function append
		* @param element A string or Phrase
		* @string[opt] propName Name of the property
		* @return self
		*/
		PhraseBuilder& append(Phrase::ChoiceValue);
		PhraseBuilder& append(Phrase::ChoiceValue, std::wstring);

		/***
		* Appends an element.
		* @function append
		* @tparam table args
		* @string args.propName Name of the property
		* @bool[opt=false] args.optional Whether this element is optional
		* @string[opt] args.asString Alias for the elements's string representation in the logs.
		* @param args.choices Either a single string or Phrase or an array of choices where a choice can be:
		* <ul>
		* <li>A table with a `propVal` and a `choice` field that is either a string or Phrase</li>
		* <li>A string or a Phrase</li>
		* </ul>
		* @return self
		* @usage
		* PhraseBuilder.new():append {
		*    propName = "what",
		*    choices = {
		*      "goodbye", -- same as {propVal = "goodbye", choice = "goodbye"}
		*      {propVal = "greeting", choice = "hi"},
		*      {
		*        propVal = "greeting",
		*        choice = PhraseBuilder.new()
		*          :append "good day"
		*          :appendOptional("sir", "extraPolite")
		*          :build()
		*      },
		*      {propVal = "greeting", choice = "hello"}
		*    },
		*  }:build()
		*/

		/***
		* Appends a multiple-choice element.
		* @function append
		* @tparam table choices An array of choices where a choice can be:
		* <ul>
		* <li>A table with a `propVal` and a `choice` field that is either a string or Phrase</li>
		* <li>A string or a Phrase</li>
		* </ul>
		* If you have Phrases in the list, consider using the above overload for readability
		* @string[opt] propName Property name.
		* @return self
		* @usage
		* PhraseBuilder.new():append({"hello", "goodbye"}, "what"):build()
		*/
		PhraseBuilder& append(LuaChoiceMap);
		PhraseBuilder& append(LuaChoiceMap, std::wstring);

		/***
		* Appends an optional element.
		* @function appendOptional
		* @param element A string or a Phrase
		* @string[opt] propName Property name.
		* @return self
		*/
		PhraseBuilder& appendOptional(Phrase::ChoiceValue);
		PhraseBuilder& appendOptional(Phrase::ChoiceValue, std::wstring);

		/***
		* Appends an optional multiple-choice element.
		* @function appendOptional
		* @param choices See above
		* @string[opt] propName Property name.
		* @return self
		*/
		PhraseBuilder& appendOptional(LuaChoiceMap);
		PhraseBuilder& appendOptional(LuaChoiceMap, std::wstring);

		/***
		* Builds the phrase
		* @function build
		* @string[opt] asString Alias for the phrase's string representation in the logs.
		* @return A Phrase object
		*/
		std::shared_ptr<Phrase> build();
		std::shared_ptr<Phrase> build(std::wstring);

	private:
		std::shared_ptr<Phrase> _build(std::wstring);
		PhraseBuilder& append(LuaChoiceMap, std::wstring, bool, std::wstring = L"");
		PhraseBuilder& append(std::vector<Phrase::PhraseElement::Choice>, std::wstring, bool, std::wstring = L"");
	};
public:
	enum class RuleState { Active, Inactive, Ignore, Disabled };
private:
	bool grammarIsDirty = false;
	std::shared_ptr<spdlog::logger> logger;
	
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
	static std::atomic<RuleID> currRuleId;
	Rule& getRuleById(RuleID ruleID);
	void changeRuleState(Rule& rule, RuleState newRuleState, SPRULESTATE spRuleState, std::string&& logMsg, std::string&& dummyLogMsg);
	CComPtr<ISpRecognizer> recognizer;
	CComPtr<ISpRecoGrammar> recoGrammar;
	CComPtr<ISpRecoContext> recoContext;
	CComPtr<ISpAudio> audio;
	void logRuleStatus(std::string& prefix, const Rule& rule);
	std::unordered_map<RuleID, Rule> rules;
	std::recursive_mutex mtx;
	std::string deviceName;
	bool checkResult(const std::string& msg, HRESULT hr);
public:
	void markGrammarDirty();
	Recognizer(std::shared_ptr<spdlog::logger>& logger, std::optional<std::string> device);
	std::string getDeviceName();
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
	void removeAllPhrases(RuleID ruleID, bool dummy);
	void setConfidence(float confidence, RuleID ruleID);
	void setRulePersistence(RulePersistenceMode persistenceMode, RuleID ruleID);
	void resetGrammar();
	void afterRecoEvent(RuleID ruleID);
	template<typename F>
	static void makeLuaBindings(sol::table ns, F fact) {
		auto RecognizerType = ns.new_usertype<Recognizer>("Recognizer", fact);
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
		ns.new_enum("RulePersistenceMode",
					 "Ignore", Recognizer::RulePersistenceMode::Ignore,
					 "Persistent", Recognizer::RulePersistenceMode::Persistent,
					 "NonPersistent", Recognizer::RulePersistenceMode::NonPersistent);

		RecognizerType["deviceName"] = &Recognizer::getDeviceName;

		auto PhraseType = ns.new_usertype<Phrase>("Phrase");

		PhraseType[sol::meta_function::to_string] = [](const Phrase& phrase) {return phrase.asString; };

		auto ResultType = ns.new_usertype<RecoResult>("RecoResult");
		ResultType["props"] = sol::readonly_property([](RecoResult& res) {return res.props; });
		ResultType["confidence"] = sol::readonly_property([](RecoResult& res) {return res.confidence; });
		ResultType["phrase"] = sol::readonly_property([](RecoResult& res) {return res.phrase; });
		using getPropRet = std::tuple<sol::optional<std::wstring>, sol::optional<RecoProp&>>;
		ResultType["getProp"] = [](RecoResult& res, sol::variadic_args va) -> getPropRet {
			if (va.leftover_count() == 0)
				throw "Invalid argument";
			std::function<sol::optional<RecoProp&>(PropTree&, size_t)> walk;
			walk = [&](PropTree& tree, size_t keyIdx) -> sol::optional<RecoProp&> {
				if (keyIdx > (va.leftover_count() - 1))
					return {};
				auto key = va.get<std::wstring>(keyIdx);
				auto it = tree.find(key);
				if (it == tree.end()) return {};
				if (keyIdx + 1 > (va.leftover_count() - 1))
					return it->second;
				return walk(it->second.children, keyIdx + 1);
			};
			sol::optional<RecoProp&> ret{};
			if (va[0].is<RecoProp>()) {
				ret = walk(va.get<RecoProp>(0).children, 1);
			} else {
				ret = walk(res.props, 0);
			}
			if (ret) {
				auto& val = ret.value();
				return std::make_tuple(val.value, ret);
			}
			return getPropRet();
		};

		auto RecoPropType = ns.new_usertype<RecoProp>("RecoProp");
		RecoPropType["value"] = sol::readonly_property([](RecoProp& prop) {return prop.value; });
		RecoPropType["confidence"] = sol::readonly_property([](RecoProp& prop) {return prop.confidence; });
		RecoPropType["children"] = sol::readonly_property([](RecoProp& prop) {return prop.children; });
		RecoPropType[sol::meta_function::to_string] = [](RecoProp& prop) {return prop.value; };

		ns.new_enum<RuleState>(
			"RuleState",
			{
				{"Active", RuleState::Active},
				{"Inactive", RuleState::Inactive},
				{"Ignore", RuleState::Ignore},
				{"Disabled", RuleState::Disabled}
			}
		);

		RecognizerType["PhraseBuilder"] = sol::readonly_property([](Recognizer& r, sol::this_state ts) {
			sol::state_view lua(ts);
			return lua.registry()[sol::light(&r)]["PhraseBuilder"];
		});

		RecognizerType["VoiceCommand"] = sol::readonly_property([](Recognizer& r, sol::this_state ts) {
			sol::state_view lua(ts);
			return lua.registry()[sol::light(&r)]["VoiceCommand"];
		});

		RecognizerType["PhraseUtils"] = sol::readonly_property([](Recognizer& r, sol::this_state ts) {
			sol::state_view lua(ts);
			return lua.registry()[sol::light(&r)]["PhraseUtils"];
		});
	}
	sol::userdata makeLuaBindingsInstance(sol::state_view&);
	RecoResult getResult();
};