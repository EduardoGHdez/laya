RSpec.describe Laya::Downloader do
  let(:cache_dir) { Dir.mktmpdir }
  let(:config) { Laya::Configuration.new(env: {}).merge(cache_dir: cache_dir) }
  let(:base_url) { "https://huggingface.co/receptron/laya-onnx/resolve/main" }
  let(:bundle_dir) { File.join(cache_dir, "receptron--laya-onnx", "main") }
  let(:bundle_files) { Laya::Configuration::BUNDLE_FILES }

  after { FileUtils.remove_entry(cache_dir) }

  def body_for(file) = "#{file}-bytes"

  def stub_downloads(prefix = base_url)
    bundle_files.each do |file|
      stub_request(:get, "#{prefix}/#{file}")
        .to_return(status: 200, body: body_for(file), headers: {"Content-Length" => body_for(file).bytesize.to_s})
    end
  end

  def populate_cache
    bundle_files.each do |file|
      path = File.join(bundle_dir, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body_for(file))
    end
  end

  describe "#call" do
    it "returns model_dir without any network access" do
      downloader = Laya::Downloader.new(config.merge(model_dir: "spec/fixtures"))

      expect(downloader.call).to eq File.expand_path("spec/fixtures")
    end

    it "downloads every bundle file into the cache" do
      stub_downloads

      expect(Laya::Downloader.new(config).call).to eq bundle_dir
      bundle_files.each do |file|
        expect(File.read(File.join(bundle_dir, file))).to eq body_for(file)
      end
    end

    it "leaves no partial files behind" do
      stub_downloads

      Laya::Downloader.new(config).call

      expect(Dir.glob(File.join(bundle_dir, "**", "*.part-*"))).to be_empty
    end

    it "reports progress per file" do
      stub_downloads
      progress = []

      Laya::Downloader.new(config.merge(on_progress: ->(**info) { progress << info })).call

      size = body_for("laya_config.json").bytesize
      expect(progress).to include({file: "laya_config.json", received: size, total: size})
    end

    it "requests files from the subfolder" do
      stub_downloads("#{base_url}/multilingual")

      Laya::Downloader.new(config.merge(subfolder: "multilingual")).call

      expect(File).to exist(File.join(bundle_dir, "multilingual", "laya.onnx"))
    end

    it "follows relative redirects" do
      stub_downloads
      stub_request(:get, "#{base_url}/tokenizer/tokenizer.json")
        .to_return(status: 307, headers: {"Location" => "/api/resolve-cache/tok.json"})
      stub_request(:get, "https://huggingface.co/api/resolve-cache/tok.json")
        .to_return(status: 200, body: "tok")

      Laya::Downloader.new(config).call

      expect(File.read(File.join(bundle_dir, "tokenizer", "tokenizer.json"))).to eq "tok"
    end

    it "sends the token to huggingface.co but not to the CDN it redirects to" do
      stub_downloads
      stub_request(:get, "#{base_url}/laya.onnx.data")
        .with(headers: {"Authorization" => "Bearer hf_secret"})
        .to_return(status: 302, headers: {"Location" => "https://cdn.example.com/blob?sig=1"})
      cdn = stub_request(:get, "https://cdn.example.com/blob?sig=1")
        .with { |request| !request.headers.key?("Authorization") }
        .to_return(status: 200, body: "weights")

      Laya::Downloader.new(config.merge(token: "hf_secret")).call

      expect(cdn).to have_been_requested
    end

    it "skips files whose size matches the remote x-linked-size" do
      populate_cache
      bundle_files.each do |file|
        stub_request(:head, "#{base_url}/#{file}").to_return(
          status: 302,
          headers: {"Location" => "https://cdn.example.com/#{file}", "X-Linked-Size" => body_for(file).bytesize.to_s}
        )
      end

      Laya::Downloader.new(config).call

      expect(a_request(:get, /huggingface/)).not_to have_been_made
    end

    it "re-downloads a file whose size differs from the remote" do
      populate_cache
      bundle_files.each do |file|
        stub_request(:head, "#{base_url}/#{file}")
          .to_return(status: 200, headers: {"Content-Length" => body_for(file).bytesize.to_s})
      end
      stub_request(:head, "#{base_url}/laya_config.json").to_return(status: 200, headers: {"Content-Length" => "3"})
      stub_request(:get, "#{base_url}/laya_config.json").to_return(status: 200, body: "new")

      Laya::Downloader.new(config).call

      expect(File.read(File.join(bundle_dir, "laya_config.json"))).to eq "new"
    end

    it "trusts a populated cache when HEAD fails (offline)" do
      populate_cache
      stub_request(:head, /huggingface/).to_raise(SocketError.new("getaddrinfo: nodename nor servname provided"))

      expect(Laya::Downloader.new(config).call).to eq bundle_dir
    end

    it "raises DownloadError with a token hint on 401" do
      stub_request(:get, "#{base_url}/laya.onnx").to_return(status: 401, body: "unauthorized")

      expect { Laya::Downloader.new(config).call }.to raise_error(Laya::DownloadError, /401.*HF_TOKEN/)
      expect(Dir.glob(File.join(bundle_dir, "**", "*")).reject { |path| File.directory?(path) }).to be_empty
    end

    it "raises DownloadError on a truncated body" do
      stub_request(:get, "#{base_url}/laya.onnx")
        .to_return(status: 200, body: "short", headers: {"Content-Length" => "100"})

      expect { Laya::Downloader.new(config).call }.to raise_error(Laya::DownloadError, /incomplete/)
      expect(File).not_to exist(File.join(bundle_dir, "laya.onnx"))
    end

    it "wraps network errors in DownloadError" do
      stub_request(:get, "#{base_url}/laya.onnx").to_raise(Errno::ECONNRESET)

      expect { Laya::Downloader.new(config).call }.to raise_error(Laya::DownloadError, /laya.onnx/)
    end
  end

  describe "#dir" do
    it "caches under <cache>/<owner>--<name>/<revision>" do
      expect(Laya::Downloader.new(config).dir).to eq bundle_dir
    end

    it "appends the subfolder, ignoring surrounding slashes" do
      expect(Laya::Downloader.new(config.merge(subfolder: "/multilingual/")).dir).to eq File.join(bundle_dir, "multilingual")
    end
  end

  describe "#missing_files" do
    it "lists every bundle file when the cache is empty" do
      expect(Laya::Downloader.new(config).missing_files).to eq bundle_files
    end

    it "is empty when every bundle file is present" do
      populate_cache

      expect(Laya::Downloader.new(config).missing_files).to eq []
    end
  end
end
