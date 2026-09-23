RSpec.describe Laya::Session do
  it "raises ModelError when the ONNX file can't be loaded" do
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "tokenizer"), dir)
      File.write(File.join(dir, "laya_config.json"), '{"max_len": 512, "head_max_len": 192}')
      File.write(File.join(dir, "laya.onnx"), "not a model")

      expect { Laya::Session.new(dir, providers: ["CPUExecutionProvider"]) }
        .to raise_error(Laya::ModelError, /could not load the model from #{dir}/)
    end
  end

  it "raises ModelError when laya_config.json is not valid JSON" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "laya_config.json"), "{")

      expect { Laya::Session.new(dir, providers: ["CPUExecutionProvider"]) }
        .to raise_error(Laya::ModelError, /could not load the model from #{dir}/)
    end
  end

  it "loads the config, tokenizer and ONNX session from the bundle", :model do
    session = Laya::Session.new(
      ENV.fetch("LAYA_MODEL_DIR"),
      providers: ["CPUExecutionProvider"],
      session_options: {intra_op_num_threads: 2}
    )

    expect(session.max_len).to eq 512
    expect(session.head_max_len).to eq 192
    expect(session.special_ids.mask).to eq 50284
  end
end
