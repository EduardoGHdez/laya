module Laya
  class Configuration
    BUNDLE_FILES = %w[laya.onnx laya.onnx.data laya_config.json
      tokenizer/tokenizer.json tokenizer/tokenizer_config.json].freeze
    SETTINGS = %i[repo revision subfolder model_dir cache_dir token providers
      session_options on_progress logger].freeze

    attr_accessor(*SETTINGS)

    def self.default_cache_dir(env)
      env["LAYA_CACHE"] ||
        File.join(env["XDG_CACHE_HOME"] ||
                  File.join(Dir.home, ".cache"), "receptron-laya")
    end

    def initialize(env: ENV)
      @repo = "receptron/laya-onnx"
      @revision = "main"
      @subfolder = nil
      @model_dir = nil
      @cache_dir = self.class.default_cache_dir(env)
      @token = env["HF_TOKEN"]
      @providers = ["CPUExecutionProvider"]
      @session_options = {}
      @on_progress = nil
      @logger = nil
    end

    def initialize_copy(source)
      super
      @providers = source.providers.dup
      @session_options = source.session_options.dup
    end

    def merge(**overrides)
      unknown = overrides.keys - SETTINGS
      raise ConfigurationError, "unknown setting(s): #{unknown.join(", ")}" if unknown.any?

      dup.tap { |copy| overrides.each { |name, value| copy.public_send(:"#{name}=", value) } }
    end

    def validate!
      raise ConfigurationError, "repo must look like \"owner/name\" (got #{repo.inspect})" unless repo.to_s.match?(%r{\A[^/\s]+/[^/\s]+\z})
      raise ConfigurationError, "revision can't be blank" if revision.to_s.empty?
      raise ConfigurationError, "providers must be an Array" unless providers.is_a?(Array)
      raise ConfigurationError, "session_options must be a Hash" unless session_options.is_a?(Hash)
      raise ConfigurationError, "on_progress must respond to #call" if on_progress && !on_progress.respond_to?(:call)

      if model_dir
        missing = BUNDLE_FILES.reject { |file| File.file?(File.join(model_dir, file)) }
        raise ConfigurationError, "model_dir #{model_dir} is missing: #{missing.join(", ")}" if missing.any?
      end
      self
    end
  end
end
