require "json"
require "onnxruntime"

module Laya
  # The loaded model: laya_config.json, the tokenizer and the ONNX Runtime session.
  class Session
    OUTPUTS = %w[logits act_probs].freeze

    attr_reader :model_config, :tokenizer

    def initialize(dir, providers:, session_options: {})
      @model_config = JSON.parse(File.read(File.join(dir, "laya_config.json")))
      @tokenizer = Tokenizer.new(dir)
      options = {graph_optimization_level: :all}.merge(session_options.transform_keys(&:to_sym))
      @onnx = OnnxRuntime::InferenceSession.new(File.join(dir, "laya.onnx"), providers: providers, **options)
    rescue OnnxRuntime::Error, JSON::ParserError, SystemCallError => e
      raise ModelError, "could not load the model from #{dir}: #{e.message}"
    end

    def special_ids = tokenizer.special_ids

    def encode(text) = tokenizer.encode(text)

    def max_len = model_config.fetch("max_len")

    def head_max_len = model_config.fetch("head_max_len")

    # inputs: the Hash from Sequence.collate. Returns [logits [B,K], act_probs [B,2]] as nested Arrays.
    def run(inputs)
      logits, act_probs = @onnx.run(OUTPUTS, inputs)
      raise ModelError, "unexpected model outputs (expected logits and act_probs)" unless logits.is_a?(Array) && act_probs.is_a?(Array)

      [logits, act_probs]
    rescue OnnxRuntime::Error => e
      raise ModelError, "inference failed: #{e.message}"
    end
  end
end
