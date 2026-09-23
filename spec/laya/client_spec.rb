# Stands in for Laya::Session so the client can be tested without the model
class FakeSession
  attr_reader :special_ids, :model_config, :calls

  def initialize(logits:, act_probs:, max_len: 512)
    @special_ids = Laya::Sequence::SpecialIds.new(cls: 1, sep: 2, mask: 3, pad: 0, mask_token: "[MASK]")
    @model_config = {
      "max_len" => max_len,
      "head_max_len" => 192,
      "temperature" => [1.0, 1.0, 1.0],
      "temperature_by_options" => {"choice:3-5" => 2.0}
    }
    @logits = logits
    @act_probs = act_probs
    @calls = []
  end

  def max_len = model_config["max_len"]

  def head_max_len = model_config["head_max_len"]

  def encode(text) = text.split.map { |word| 100 + word.size }

  def run(inputs)
    @calls << inputs
    [@logits, @act_probs]
  end
end

RSpec.describe Laya::Client do
  let(:config) { Laya::Configuration.new(env: {}) }

  let(:questions) do
    {
      department: {
        type: :choice,
        instructions: "Which team?",
        criteria: {billing: "payments", support: "bugs", sales: "purchases"}
      },
      urgency: {
        type: :score,
        instructions: "How urgent?",
        criteria: %w[low some high top]
      },
      churn: {
        type: :noul,
        instructions: "Will they cancel?"
      }
    }
  end

  let(:session) do
    FakeSession.new(
      logits: [[4.0, 0.0, 0.0, -1e4], [0.0, 1.0, 2.0, 0.0], [0.0, 1.0, -1e4, -1e4]],
      act_probs: [[0.8, 0.2], [0.6, 0.4], [0.3, 0.7]]
    )
  end

  describe "#system_one" do
    subject(:result) { Laya::Client.new(config, session: session).system_one({ticket: "refund please"}, questions) }

    it "runs every question in one forward pass" do
      result

      expect(session.calls.size).to eq 1
    end

    it "sends each question's type id and option markers to the model" do
      result

      expect(session.calls.first[:qtype]).to eq [0, 1, 2]
      expect(session.calls.first[:marker_mask]).to eq [
        [true, true, true, false],
        [true, true, true, true],
        [true, true, false, false]
      ]
    end

    it "decodes a choice with the per-cardinality temperature" do
      answer = result[:department]

      expect(answer).to be_a Laya::ChoiceAnswer
      expect(answer.choice).to eq "billing"
      expect(answer.probabilities).to eq({"billing" => 0.787, "support" => 0.1065, "sales" => 0.1065})
      expect(answer.confidence).to eq 0.3942
      expect(answer.act_probability).to eq 0.8
    end

    it "decodes a score as the expected level" do
      answer = result[:urgency]

      expect(answer).to be_a Laya::ScoreAnswer
      expect(answer.score).to eq 1.6929
      expect(answer.probabilities).to eq({"0" => 0.0826, "1" => 0.2245, "2" => 0.6103, "3" => 0.0826})
      expect(answer.legend).to eq({"0" => "low", "1" => "some", "2" => "high", "3" => "top"})
      expect(answer.confidence).to eq 0.2435
    end

    it "decodes a noul as P(true)" do
      answer = result[:churn]

      expect(answer).to be_a Laya::NoulAnswer
      expect(answer.noul).to eq 0.7311
      expect(answer.act_probability).to eq 0.3
    end

    it "reports the model name and token usage" do
      expect(result.model).to eq "laya"
      expect(result.usage.input_tokens).to eq session.calls.first[:attention_mask].flatten.sum
      expect(result.usage.output_tokens).to eq 0
    end

    it "keeps the caller's keys" do
      client = Laya::Client.new(config, session: session)

      result = client.system_one("state", questions.transform_keys(&:to_s))

      expect(result.answers.keys).to eq %w[department urgency churn]
    end

    it "raises InputTooLongError when options don't fit in max_len" do
      client = Laya::Client.new(config, session: FakeSession.new(logits: [], act_probs: [], max_len: 8))

      expect { client.system_one("state", questions) }
        .to raise_error(Laya::InputTooLongError, "question :department: options do not fit in head_max_len=192 tokens")
    end

    it "validates questions before loading the model" do
      client = Laya::Client.new(config)

      expect { client.system_one("state", {}) }.to raise_error(Laya::InvalidQuestionError)
      expect(client).not_to be_loaded
    end
  end

  describe "lazy loading" do
    let(:downloader) { instance_double(Laya::Downloader, call: "/models") }

    before do
      allow(Laya::Downloader).to receive(:new).and_return(downloader)
      allow(Laya::Session).to receive(:new).and_return(session)
    end

    it "does no work until needed" do
      client = Laya::Client.new(config)

      expect(client).not_to be_loaded
      expect(Laya::Session).not_to have_received(:new)
    end

    it "loads on load! and returns the client" do
      client = Laya::Client.new(config)

      expect(client.load!).to be client
      expect(client).to be_loaded
    end

    it "passes providers and session options to the session" do
      Laya::Client.new(config.merge(session_options: {intra_op_num_threads: 2})).load!

      expect(Laya::Session).to have_received(:new)
        .with("/models", providers: ["CPUExecutionProvider"], session_options: {intra_op_num_threads: 2})
    end

    it "loads once even when several threads call load!" do
      client = Laya::Client.new(config)

      Array.new(4) { Thread.new { client.load! } }.each(&:join)

      expect(Laya::Session).to have_received(:new).once
    end

    it "reloads after close" do
      client = Laya::Client.new(config).load!

      client.close

      expect(client).not_to be_loaded
      client.load!
      expect(Laya::Session).to have_received(:new).twice
    end
  end

  it "freezes its configuration" do
    client = Laya::Client.new(config)

    expect(client.config).to be_frozen
    expect { client.config.revision = "x" }.to raise_error(FrozenError)
  end
end

RSpec.describe "Laya.new and Laya.download" do
  after { Laya.reset_config! }

  it "builds a client from the global config plus overrides" do
    Laya.configure { |config| config.revision = "v1" }

    client = Laya.new(cache_dir: "/tmp/laya-test")

    expect(client).to be_a Laya::Client
    expect(client.config.revision).to eq "v1"
    expect(client.config.cache_dir).to eq "/tmp/laya-test"
  end

  it "leaves the global config untouched" do
    Laya.new(cache_dir: "/tmp/laya-test")

    expect(Laya.config.cache_dir).not_to eq "/tmp/laya-test"
  end

  it "rejects an invalid configuration up front" do
    expect { Laya.new(repo: "nope") }.to raise_error(Laya::ConfigurationError)
  end

  it "downloads with the merged config and returns the directory" do
    downloader = instance_double(Laya::Downloader, call: "/cache/dir")
    allow(Laya::Downloader).to receive(:new).and_return(downloader)

    expect(Laya.download(revision: "v2")).to eq "/cache/dir"
    expect(Laya::Downloader).to have_received(:new).with(having_attributes(revision: "v2"))
  end
end
