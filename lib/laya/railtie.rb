module Laya
  # Registers the Rake tasks in Rails apps, after the app boots so config/initializers/laya.rb applies.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks.rb", __dir__)
      %w[laya:download laya:path].each { |name| Rake::Task[name].enhance([:environment]) }
    end
  end
end
