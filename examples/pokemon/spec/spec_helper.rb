require "laya"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end

Dir[File.join(__dir__, "support/*.rb")].each { |file| require file }
