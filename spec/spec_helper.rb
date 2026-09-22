require "laya"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require "webmock/rspec"

FIXTURES = File.expand_path("fixtures", __dir__)

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding :model unless ENV["LAYA_MODEL_DIR"]
end
