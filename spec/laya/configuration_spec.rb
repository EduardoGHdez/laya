RSpec.describe Laya::Configuration do
  subject(:config) { Laya::Configuration.new(env: {}) }

  describe "defaults" do
    it "points at the published bundle on the CPU" do
      expect(config.repo).to eq "receptron/laya-onnx"
      expect(config.revision).to eq "main"
      expect(config.subfolder).to be_nil
      expect(config.model_dir).to be_nil
      expect(config.token).to be_nil
      expect(config.providers).to eq ["CPUExecutionProvider"]
      expect(config.session_options).to eq({})
      expect(config.on_progress).to be_nil
      expect(config.logger).to be_nil
    end

    it "prefers cache folder under ~/.cache" do
      expect(config.cache_dir).to eq File.join(Dir.home, ".cache", "receptron-laya")
    end

    it "prefers XDG_CACHE_HOME, then LAYA_CACHE" do
      expect(
        Laya::Configuration.new(env: {"XDG_CACHE_HOME" => "/xdg"}).cache_dir
      ).to eq "/xdg/receptron-laya"

      expect(
        Laya::Configuration.new(env: {"XDG_CACHE_HOME" => "/xdg", "LAYA_CACHE" => "/laya"}).cache_dir
      ).to eq "/laya"
    end

    it "reads HF_TOKEN" do
      expect(
        Laya::Configuration.new(env: {"HF_TOKEN" => "hf_x"}).token
      ).to eq "hf_x"
    end
  end

  describe "#merge" do
    it "returns a copy with the overrides applied" do
      copy = config.merge(revision: "v1", cache_dir: "/tmp/c")

      expect([copy.revision, copy.cache_dir]).to eq ["v1", "/tmp/c"]
      expect(config.revision).to eq "main"
    end

    it "does not share mutable settings with the original" do
      copy = config.merge
      copy.providers << "CoreMLExecutionProvider"
      copy.session_options[:intra_op_num_threads] = 2

      expect(config.providers).to eq ["CPUExecutionProvider"]
      expect(config.session_options).to eq({})
    end

    it "rejects unknown settings" do
      expect { config.merge(variant: :multilingual) }
        .to raise_error(Laya::ConfigurationError, /unknown setting.*variant/)
    end
  end

  describe "#validate!" do
    it "returns self when valid" do
      expect(config.validate!).to be config
    end

    it "rejects a malformed repo" do
      expect { config.merge(repo: "laya").validate! }.to raise_error(Laya::ConfigurationError, /repo/)
    end

    it "rejects a blank revision" do
      expect { config.merge(revision: "").validate! }.to raise_error(Laya::ConfigurationError, /revision/)
    end

    it "rejects non-Array providers and non-Hash session_options" do
      expect { config.merge(providers: "cpu").validate! }.to raise_error(Laya::ConfigurationError, /providers/)
      expect { config.merge(session_options: []).validate! }.to raise_error(Laya::ConfigurationError, /session_options/)
    end

    it "rejects an on_progress that can't be called" do
      expect { config.merge(on_progress: "nope").validate! }.to raise_error(Laya::ConfigurationError, /on_progress/)
    end

    it "lists the bundle files missing from model_dir" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "laya.onnx"), "")
        expect { config.merge(model_dir: dir).validate! }
          .to raise_error(Laya::ConfigurationError, %r{missing: laya.onnx.data, laya_config.json, tokenizer/tokenizer.json})
      end
    end
  end
end

RSpec.describe "Laya global configuration" do
  after { Laya.reset_config! }

  it "yields and returns the global config" do
    returned = Laya.configure { |c| c.revision = "v2" }
    expect(returned).to be Laya.config
    expect(Laya.config.revision).to eq "v2"
  end

  it "resets to defaults" do
    Laya.configure { |c| c.revision = "v2" }
    Laya.reset_config!
    expect(Laya.config.revision).to eq "main"
  end
end
