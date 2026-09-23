require_relative "laya/version"
require_relative "laya/errors"
require_relative "laya/configuration"
require_relative "laya/questions"
require_relative "laya/sequence"
require_relative "laya/result"
require_relative "laya/tokenizer"
require_relative "laya/session"
require_relative "laya/downloader"
require_relative "laya/client"

module Laya
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    def reset_config!
      @config = Configuration.new
    end

    # A client with the global config plus overrides. Cheap: the model loads on first use or load!.
    def new(**overrides)
      Client.new(config.merge(**overrides))
    end

    # Fetch the model files without loading them (Docker builds, CI caches). Returns the directory.
    def download(**overrides)
      Downloader.new(config.merge(**overrides).validate!).call
    end
  end
end
