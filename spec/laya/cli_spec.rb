RSpec.describe Laya::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def run(*argv, env: {}) = Laya::CLI.new(out: out, err: err, env: env).run(argv)

  after { Laya.reset_config! }

  describe "download" do
    it "prints the model directory and returns 0" do
      allow(Laya::Downloader).to receive(:new).and_return(instance_double(Laya::Downloader, call: "/cache/dir", dir: "/cache/dir"))

      expect(run("download")).to eq 0
      expect(out.string).to eq "/cache/dir\n"
    end

    it "applies ENV overrides on top of the config" do
      allow(Laya::Downloader).to receive(:new).and_return(instance_double(Laya::Downloader, call: "/cache/dir", dir: "/cache/dir"))

      run("download", env: {"LAYA_REVISION" => "v1", "LAYA_CACHE" => "/c", "HF_TOKEN" => "hf_x"})

      expect(Laya::Downloader).to have_received(:new)
        .with(having_attributes(revision: "v1", cache_dir: "/c", token: "hf_x"))
    end

    it "announces where it downloads and when the model is ready" do
      allow(Laya::Downloader).to receive(:new).and_return(instance_double(Laya::Downloader, call: "/cache/dir", dir: "/cache/dir"))

      run("download")

      expect(err.string).to eq "Downloading receptron/laya-onnx@main into /cache/dir\nModel ready in /cache/dir\n"
    end

    it "shows per-file progress in megabytes" do
      downloader = instance_double(Laya::Downloader, dir: "/cache/dir")
      allow(Laya::Downloader).to receive(:new) do |config|
        allow(downloader).to receive(:call) do
          config.on_progress.call(file: "laya.onnx.data", received: 524_288, total: 1_048_576)
          config.on_progress.call(file: "laya.onnx.data", received: 1_048_576, total: 1_048_576)
          "/cache/dir"
        end
        downloader
      end

      run("download")

      expect(err.string).to include "\r  laya.onnx.data                    50%  0.5 MB / 1.0 MB"
      expect(err.string).to include "\r  laya.onnx.data                   100%  1.0 MB / 1.0 MB\n"
    end

    it "prints the error and returns 1 on failure" do
      allow(Laya::Downloader).to receive(:new).and_raise(Laya::DownloadError, "failed to download x: 500")

      expect(run("download")).to eq 1
      expect(err.string).to include "laya: failed to download x: 500"
    end
  end

  describe "path" do
    it "prints the model directory when every file is present" do
      Dir.mktmpdir do |dir|
        Laya::Configuration::BUNDLE_FILES.each do |file|
          FileUtils.mkdir_p(File.dirname(File.join(dir, file)))
          File.write(File.join(dir, file), "")
        end
        Laya.configure { |config| config.model_dir = dir }

        expect(run("path")).to eq 0
        expect(out.string).to eq "#{File.expand_path(dir)}\n"
      end
    end

    it "returns 1 and lists the missing files" do
      Dir.mktmpdir do |dir|
        expect(run("path", env: {"LAYA_CACHE" => dir})).to eq 1
        expect(err.string).to include "is missing:\n  laya.onnx\n  laya.onnx.data\n"
        expect(err.string).to include "Run `laya download` to fetch them."
      end
    end
  end

  describe "help" do
    it "prints the commands, environment and examples on stdout" do
      expect(run("help")).to eq 0
      expect(out.string).to include "laya #{Laya::VERSION}: manage the Laya model files"
      expect(out.string).to include "laya download   Download the model into the cache"
      expect(out.string).to include "LAYA_REVISION   Branch, tag or commit   main"
      expect(out.string).to include "Examples:"
    end

    it "accepts -h and --help" do
      expect(run("-h")).to eq 0
      expect(run("--help")).to eq 0
    end

    it "shows the current values of the settings, with ENV applied" do
      run("help", env: {"LAYA_CACHE" => "/models", "HF_TOKEN" => "hf_x"})

      expect(out.string).to include "LAYA_CACHE      Cache directory         /models"
      expect(out.string).to include "HF_TOKEN        Hugging Face token      set"
    end

    it "never prints the token itself" do
      run("help", env: {"HF_TOKEN" => "hf_secret"})

      expect(out.string).not_to include "hf_secret"
    end

    it "prints help on stderr and returns 64 without a command" do
      expect(run).to eq 64
      expect(err.string).to include "Usage:"
    end

    it "names an unknown command before the help and returns 64" do
      expect(run("nope")).to eq 64
      expect(err.string).to start_with "laya: unknown command \"nope\"\n\nlaya #{Laya::VERSION}"
    end
  end
end
