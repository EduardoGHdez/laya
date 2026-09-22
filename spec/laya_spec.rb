RSpec.describe Laya do
  it "has a version" do
    expect(Laya::VERSION).to eq "0.1.0"
  end

  it "roots every error at Laya::Error" do
    [
      Laya::ConfigurationError,
      Laya::InvalidQuestionError,
      Laya::InputTooLongError,
      Laya::DownloadError,
      Laya::ModelError
    ].each do |klass|
      expect(klass.ancestors).to include(Laya::Error)
    end
  end
end
