require_relative "laya/version"
require_relative "laya/errors"
require_relative "laya/configuration"

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
