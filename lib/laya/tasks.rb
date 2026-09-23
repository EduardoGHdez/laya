require "rake"
require "laya"

namespace :laya do
  desc "Download the Laya model files into the cache"
  task :download do
    status = Laya::CLI.new.run(["download"])
    exit(status) unless status.zero?
  end

  desc "Print the directory holding the Laya model files"
  task :path do
    status = Laya::CLI.new.run(["path"])
    exit(status) unless status.zero?
  end
end
