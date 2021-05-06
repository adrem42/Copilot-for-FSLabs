
return {

  engModeSelector = {
    label = "engModeSelector",
    displayLabel = "Engine Mode Selector",
    response = {
      NORM = VoiceCommand:new "normal", 
      ["IGN/START"] = VoiceCommand:new "ignition"
    },
    onResponse = function(check, label)
      check(
        FSL.PED_ENG_MODE_Switch:getPosn() == label,
        "Eng mode switch position isn't " .. label
      )
    end
  },
  
  baroRefQNH = {
    label = "baroRef",
    displayLabel = "Baro REF",
    response = VoiceCommand:new(
      PhraseBuilder.new()
        :appendOptional "QNH"
        :append{PhraseUtils.getPhrase("spelledNumber", 3), PhraseUtils.getPhrase("spelledNumber", 4)}
        :appendOptional "set"
        :build(),
      0.9
    )
  }
}