require "rake"

RSpec.describe "laya rake tasks" do
  around do |example|
    original_application = Rake.application
    Rake::TaskManager.record_task_metadata = true # keep desc comments outside `rake -T`
    Rake.application = Rake::Application.new
    load File.expand_path("../../lib/laya/tasks.rb", __dir__)
    example.run
  ensure
    Rake.application = original_application
  end

  it "defines laya:download with a description" do
    expect(Rake::Task["laya:download"].comment).to eq "Download the Laya model files into the cache"
  end

  it "defines laya:path with a description" do
    expect(Rake::Task["laya:path"].comment).to eq "Print the directory holding the Laya model files"
  end

  it "runs the matching CLI command" do
    cli = instance_double(Laya::CLI, run: 0)
    allow(Laya::CLI).to receive(:new).and_return(cli)

    Rake::Task["laya:path"].execute

    expect(cli).to have_received(:run).with(["path"])
  end

  it "exits with the CLI status on failure" do
    allow(Laya::CLI).to receive(:new).and_return(instance_double(Laya::CLI, run: 1))

    expect { Rake::Task["laya:download"].execute }
      .to raise_error(SystemExit) { |error| expect(error.status).to eq 1 }
  end
end
