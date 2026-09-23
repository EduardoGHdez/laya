module Laya
  # Answers typed questions about a state. Loading is lazy (first call, or load!) and thread-safe.
  class Client
    attr_reader :config

    def initialize(config, session: nil)
      @config = config.validate!.freeze
      @session = session
      @mutex = Mutex.new
    end

    def load!
      session
      self
    end

    def loaded? = !@session.nil?

    def close
      @mutex.synchronize { @session = nil }
      nil
    end

    def predict(state, questions)
      normalized_questions = Questions.normalize_all(questions)
      model = session
      encoded = {}
      encode = ->(text) { encoded[text] ||= model.encode(text) }

      rows = normalized_questions.map do |key, question|
        built = Sequence.build(encode, model.special_ids, state, question, max_len: model.max_len, head_max_len: model.head_max_len)
        if built.markers.size != question.options.size
          raise InputTooLongError, "question #{key.inspect}: options do not fit in head_max_len=#{model.head_max_len} tokens"
        end

        [built, question.type_id]
      end

      logits, act_probs = model.run(Sequence.collate(rows, pad: model.special_ids.pad))

      answers = normalized_questions.each_with_index.to_h do |(key, question), row|
        option_count = rows[row].first.markers.size
        [key, decode(question, logits[row].first(option_count), act_probs[row][0], model.model_config)]
      end

      Result.new(
        model: "laya",
        answers: answers.freeze,
        usage: Usage.new(input_tokens: rows.sum { |built, _| built.ids.size }, output_tokens: 0)
      )
    end
    alias_method :system_one, :predict

    private

    def session
      @session || @mutex.synchronize do
        @session ||= Session.new(Downloader.new(config).call, providers: config.providers, session_options: config.session_options)
      end
    end

    def decode(question, logits, act_probability, model_config)
      temperature = Sequence.temperature(model_config, question.type, logits.size)
      probabilities = Sequence.softmax(logits.map { |logit| logit / temperature })

      case question.type
      when "choice"
        labels = question.criteria.keys
        ChoiceAnswer.new(
          choice: labels[probabilities.index(probabilities.max)],
          probabilities: labels.zip(probabilities.map { |probability| probability.round(4) }).to_h.freeze,
          confidence: Sequence.confidence(probabilities).round(4),
          act_probability: act_probability
        )
      when "score"
        ScoreAnswer.new(
          score: probabilities.each_with_index.sum { |probability, level| probability * level }.round(4),
          probabilities: probabilities.each_with_index.to_h { |probability, level| [level.to_s, probability.round(4)] }.freeze,
          legend: question.criteria.each_with_index.to_h { |description, level| [level.to_s, description] }.freeze,
          confidence: Sequence.confidence(probabilities).round(4),
          act_probability: act_probability
        )
      else
        NoulAnswer.new(noul: probabilities[1].round(4), act_probability: act_probability)
      end
    end
  end
end
