module Laya
  Usage = Data.define(:input_tokens, :output_tokens)

  ChoiceAnswer = Data.define(:choice, :probabilities, :confidence, :act_probability) do
    def type = "choice"

    def to_h
      {
        type: type,
        choice: choice,
        probabilities: probabilities,
        confidence: confidence,
        rl_agent: {act_probability: act_probability}
      }
    end
  end

  ScoreAnswer = Data.define(:score, :probabilities, :legend, :confidence, :act_probability) do
    def type = "score"

    def to_h
      {
        type: type,
        score: score,
        legend: legend,
        probabilities: probabilities,
        confidence: confidence,
        rl_agent: {act_probability: act_probability}
      }
    end
  end

  NoulAnswer = Data.define(:noul, :act_probability) do
    def type = "noul"

    def to_h
      {
        type: type,
        noul: noul,
        rl_agent: {act_probability: act_probability}
      }
    end
  end

  Result = Data.define(:model, :answers, :usage) do
    def [](key) = answers[key]

    def to_h
      {
        model: model,
        answers: answers.transform_values(&:to_h),
        usage: usage.to_h
      }
    end
  end
end
