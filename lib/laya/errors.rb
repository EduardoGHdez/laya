module Laya
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class InvalidQuestionError < Error; end

  class InputTooLongError < Error; end

  class DownloadError < Error; end

  class ModelError < Error; end
end
