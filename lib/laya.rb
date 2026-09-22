require_relative "laya/version"
require_relative "laya/errors"
require_relative "laya/configuration"
require_relative "laya/questions"
require_relative "laya/sequence"
require_relative "laya/result"
require_relative "laya/tokenizer"

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
  end
end
