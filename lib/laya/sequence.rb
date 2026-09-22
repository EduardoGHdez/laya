require "json"

module Laya
  module Sequence
    SpecialIds = Data.define(:cls, :sep, :mask, :pad, :mask_token)
    Built = Data.define(:ids, :markers)

    OPTION_TOKEN_CAP = 48
    MIN_OPTION_BUDGET = 16
    MIN_TOKENS_PER_OPTION = 4
    MIN_HEAD_TOKENS = 8

    module_function

    def serialize_state(state) = state.is_a?(String) ? state : JSON.generate(state)

    def build(encode, special_ids, state, question, max_len:, head_max_len:)
      scrub = ->(text) { text.gsub(special_ids.mask_token, " ") }

      head_ids = encode.call("#{question.type} question: #{scrub.call(question.instructions)}")
      option_ids = question.options.map do |option|
        [special_ids.mask] + encode.call(" " + scrub.call(option)).first(OPTION_TOKEN_CAP)
      end

      budget = head_max_len - option_ids.sum(&:size)
      if budget < MIN_OPTION_BUDGET # too many / too long options: shrink every option text evenly
        per_option = [MIN_TOKENS_PER_OPTION, (head_max_len - MIN_OPTION_BUDGET) / [1, option_ids.size].max].max
        option_ids = option_ids.map { |ids| ids.first(per_option) }
        budget = head_max_len - option_ids.sum(&:size)
      end

      ids = [special_ids.cls, *head_ids.first([MIN_HEAD_TOKENS, budget].max), special_ids.sep]
      markers = option_ids.map { |option| ids.size.tap { ids.concat(option) } }
      ids << special_ids.sep

      room = [0, max_len - ids.size - 1].max
      ids.concat(encode.call(scrub.call(serialize_state(state))).first(room))
      ids << special_ids.sep

      Built.new(ids: ids.first(max_len), markers: markers.select { |marker| marker < max_len })
    end

    def collate(rows, pad:)
      length = rows.map { |built, _| built.ids.size }.max
      width = rows.map { |built, _| built.markers.size }.max

      {
        input_ids: rows.map { |built, _| built.ids + [pad] * (length - built.ids.size) },
        attention_mask: rows.map { |built, _| [1] * built.ids.size + [0] * (length - built.ids.size) },
        marker_pos: rows.map { |built, _| built.markers + [0] * (width - built.markers.size) },
        marker_mask: rows.map { |built, _| [true] * built.markers.size + [false] * (width - built.markers.size) },
        qtype: rows.map { |_, type_id| type_id }
      }
    end

    def temp_bucket(type, option_count)
      size =
        if option_count <= 2 then "2"
        elsif option_count <= 5 then "3-5"
        elsif option_count <= 10 then "6-10"
        else "11+"
        end

      "#{type}:#{size}"
    end

    def temperature(model_config, type, option_count)
      model_config.fetch("temperature_by_options", {})[temp_bucket(type, option_count)] ||
        model_config.fetch("temperature", [])[Questions::TYPES.fetch(type)] ||
        1.0
    end

    def softmax(logits)
      max = logits.max
      exponentials = logits.map { |logit| Math.exp(logit - max) }
      sum = exponentials.sum

      exponentials.map { |exponential| exponential / sum }
    end

    def confidence(probabilities)
      return 1.0 if probabilities.size < 2

      entropy = -probabilities.sum { |probability| probability * Math.log([probability, 1e-12].max) }
      1 - entropy / Math.log(probabilities.size)
    end
  end
end
