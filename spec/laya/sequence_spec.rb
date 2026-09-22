RSpec.describe Laya::Sequence do
  let(:special_ids) { Laya::Sequence::SpecialIds.new(cls: 1, sep: 2, mask: 3, pad: 0, mask_token: "[MASK]") }

  let(:encode) { ->(text) { text.split.map { |word| (word == "[MASK]") ? 3 : 100 + word.size } } }

  def build(state, question_definition, max_len: 512, head_max_len: 192)
    question = Laya::Questions.normalize(:q, question_definition)

    Laya::Sequence.build(encode, special_ids, state, question, max_len: max_len, head_max_len: head_max_len)
  end

  describe ".build" do
    it "lays out [CLS] head [SEP] ([MASK] option)* [SEP] state [SEP]" do
      built = build("hello world", {
        type: :choice,
        instructions: "which one",
        criteria: %w[a bb]
      })

      expect(built.ids.first).to eq 1
      expect(built.ids[5]).to eq 2
      expect(built.markers).to eq [6, 8]
      expect(built.ids.values_at(6, 8)).to eq [3, 3]
      expect(built.ids.last(4)).to eq [2, 105, 105, 2]
    end

    it "serializes a non-String state as JSON" do
      built = build({a: 1}, {type: :noul, instructions: "is it"})

      expect(built.ids[-2]).to eq 107
    end

    it "truncates the state to max_len and keeps the final [SEP]" do
      built = build("w " * 1000, {type: :noul, instructions: "is it"}, max_len: 64, head_max_len: 32)

      expect(built.ids.size).to eq 64
      expect(built.ids.last).to eq 2
      expect(built.markers.size).to eq 2
    end

    it "scrubs the mask token from instructions, options and state" do
      built = build("state [MASK] here", {
        type: :choice,
        instructions: "x [MASK] y",
        criteria: ["[MASK] a", "b"]
      })

      expect(built.ids.count(3)).to eq 2
    end

    it "shrinks every option evenly and trims the head when options overflow head_max_len" do
      options = Array.new(30) { |i| "opt#{i} #{"word " * 9}" }

      built = build("s", {type: :choice, instructions: "word " * 20, criteria: options}, head_max_len: 64)

      expect(built.markers.first).to eq 10 # [CLS] + 8 head tokens + [SEP]
      expect(built.markers.each_cons(2).map { |a, b| b - a }.uniq).to eq [4] # (64 - 16) / 30 < 4, so 4
    end

    it "caps each option at 48 tokens plus its marker" do
      built = build("s", {type: :choice, instructions: "i", criteria: ["long " * 60, "b"]})

      expect(built.markers[1] - built.markers[0]).to eq 49
    end

    it "drops markers that fall past max_len" do
      options = Array.new(10) { |i| "a#{i} b c d e" }

      built = build("s", {type: :choice, instructions: "pick", criteria: options}, max_len: 20)

      expect(built.markers).to eq [5, 11, 17]
      expect(built.ids.size).to eq 20
    end
  end

  describe ".collate" do
    it "right-pads ids and markers across the batch" do
      short = Laya::Sequence::Built.new(ids: [1, 5, 2], markers: [1])
      long = Laya::Sequence::Built.new(ids: [1, 5, 6, 7, 2], markers: [1, 3])

      inputs = Laya::Sequence.collate([[short, 2], [long, 0]], pad: 9)

      expect(inputs).to eq(
        input_ids: [[1, 5, 2, 9, 9], [1, 5, 6, 7, 2]],
        attention_mask: [[1, 1, 1, 0, 0], [1, 1, 1, 1, 1]],
        marker_pos: [[1, 0], [1, 3]],
        marker_mask: [[true, false], [true, true]],
        qtype: [2, 0]
      )
    end
  end

  describe ".temp_bucket" do
    it "uses the 2 bucket up to 2 options" do
      expect(Laya::Sequence.temp_bucket("noul", 2)).to eq "noul:2"
      expect(Laya::Sequence.temp_bucket("choice", 0)).to eq "choice:2"
    end

    it "uses the 3-5 bucket from 3 to 5 options" do
      expect(Laya::Sequence.temp_bucket("choice", 3)).to eq "choice:3-5"
      expect(Laya::Sequence.temp_bucket("choice", 5)).to eq "choice:3-5"
    end

    it "uses the 6-10 bucket from 6 to 10 options" do
      expect(Laya::Sequence.temp_bucket("choice", 6)).to eq "choice:6-10"
      expect(Laya::Sequence.temp_bucket("choice", 10)).to eq "choice:6-10"
    end

    it "uses the 11+ bucket from 11 options" do
      expect(Laya::Sequence.temp_bucket("choice", 11)).to eq "choice:11+"
      expect(Laya::Sequence.temp_bucket("choice", 100)).to eq "choice:11+"
    end
  end

  describe ".temperature" do
    let(:model_config) do
      {
        "temperature" => [1.5, 1.2, 1.9],
        "temperature_by_options" => {"choice:3-5" => 1.7}
      }
    end

    it "prefers the per-cardinality temperature" do
      expect(Laya::Sequence.temperature(model_config, "choice", 3)).to eq 1.7
    end

    it "falls back to the per-type temperature" do
      expect(Laya::Sequence.temperature(model_config, "choice", 2)).to eq 1.5
      expect(Laya::Sequence.temperature(model_config, "noul", 2)).to eq 1.9
    end

    it "falls back to 1.0 when the config has no temperatures" do
      expect(Laya::Sequence.temperature({}, "score", 4)).to eq 1.0
    end
  end

  describe ".softmax" do
    it "splits evenly between equal logits" do
      expect(Laya::Sequence.softmax([0.0, 0.0])).to eq [0.5, 0.5]
    end

    it "stays numerically stable with large logits" do
      expect(Laya::Sequence.softmax([1000.0, 1000.0])).to eq [0.5, 0.5]
    end

    it "matches the reference values" do
      probabilities = Laya::Sequence.softmax([2.0, 0.0, 0.0])

      expect(probabilities.map { |probability| probability.round(4) }).to eq [0.787, 0.1065, 0.1065]
    end
  end

  describe ".confidence" do
    it "is 0 for a uniform distribution" do
      expect(Laya::Sequence.confidence([0.25] * 4)).to be_within(1e-12).of(0.0)
    end

    it "is 1 for a certain answer" do
      expect(Laya::Sequence.confidence([1.0, 0.0])).to be_within(1e-9).of(1.0)
    end

    it "is 1 when there is a single option" do
      expect(Laya::Sequence.confidence([1.0])).to eq 1.0
    end

    it "is 1 minus the normalized entropy" do
      probabilities = Laya::Sequence.softmax([2.0, 0.0, 0.0])

      expect(Laya::Sequence.confidence(probabilities).round(4)).to eq 0.3942
    end
  end
end
