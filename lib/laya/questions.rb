require "json"

module Laya
  # Validates Jev-style question hashes and normalizes them (rl_agent_api.RLAgent._to_internal).
  module Questions
    TYPES = {"choice" => 0, "score" => 1, "noul" => 2}.freeze
    NOUL_DEFAULTS = {
      "false" => "no, the statement does not hold",
      "true" => "yes, the statement holds"
    }.freeze

    Question = Data.define(:type, :instructions, :criteria) do
      def type_id = TYPES.fetch(type)

      def options
        case type
        when "choice"
          criteria.map { |label, desc| desc.to_s.empty? ? label : "#{label}: #{desc}" }
        when "score"
          criteria.each_with_index.map { |level, i| "level #{i}: #{level}" }
        else
          %w[false true].map do |k|
            "#{k}: #{criteria[k].to_s.empty? ? NOUL_DEFAULTS[k] : criteria[k]}"
          end
        end
      end
    end

    module_function

    def normalize_all(questions)
      raise InvalidQuestionError, "questions must be a Hash of name => question" unless questions.is_a?(Hash)
      raise InvalidQuestionError, "at least one question is required" if questions.empty?

      questions.to_h { |key, question_definition| [key, normalize(key, question_definition)] }
    end

    def normalize(key, question_definition)
      invalid!(key, "must be a Hash") unless question_definition.is_a?(Hash)
      attributes = question_definition.transform_keys(&:to_s)
      type = attributes["type"].to_s
      invalid!(key, "type must be one of choice, score, noul (got #{attributes["type"].inspect})") unless TYPES.key?(type)

      Question.new(
        type: type,
        instructions: instructions(key, attributes["instructions"]),
        criteria: criteria(key, type, attributes["criteria"])
      )
    end

    def instructions(key, value)
      case value
      when String
        invalid!(key, "instructions can't be blank") if value.strip.empty?
        value
      when Hash then JSON.generate(value)
      else invalid!(key, "instructions must be a String or Hash")
      end
    end

    def criteria(key, type, value)
      case type
      when "choice" then choice_criteria(key, value)
      when "score" then score_criteria(key, value)
      else noul_criteria(key, value)
      end
    end

    def choice_criteria(key, value)
      pairs =
        case value
        when Hash then value.map { |label, desc| [label.to_s, desc&.to_s] }
        when Array then value.map { |label| [label.to_s, nil] }
        else invalid!(key, "choice criteria must be a Hash of label => description or an Array of labels")
        end
      invalid!(key, "choice needs at least 2 options") if pairs.size < 2
      invalid!(key, "choice labels must be unique") if pairs.map(&:first).uniq.size != pairs.size
      pairs.to_h
    end

    def score_criteria(key, value)
      invalid!(key, "score criteria must be an Array of levels, lowest first") unless value.is_a?(Array)
      invalid!(key, "score needs at least 2 levels") if value.size < 2
      value.map(&:to_s)
    end

    def noul_criteria(key, value)
      return {} if value.nil?

      crit = value.is_a?(Hash) ? value.to_h { |k, v| [k.to_s, v&.to_s] } : nil
      invalid!(key, "noul criteria must be a Hash with only true and false keys") unless crit && (crit.keys - %w[true false]).empty?
      crit
    end

    def invalid!(key, message)
      raise InvalidQuestionError, "question #{key.inspect}: #{message}"
    end
  end
end
