RSpec.describe Laya::Tokenizer do
  subject(:tokenizer) { Laya::Tokenizer.new(FIXTURES) }

  let(:reference) { JSON.parse(File.read(File.join(FIXTURES, "reference_sequences.json"))) }

  let(:ticket_state) do
    {
      subject: "Refund not received",
      body: "I cancelled my subscription two weeks ago and I still have not received my refund. " \
        "This is the third time I am writing. If this is not resolved I will dispute the charge with my bank."
    }
  end

  let(:ticket_questions) do
    {
      department: {
        type: :choice,
        instructions: "Which team should handle this ticket?",
        criteria: {billing: "payments, refunds, invoices", support: "product help and bugs", sales: "new purchases and upgrades"}
      },
      urgency: {
        type: :score,
        instructions: "How urgent is this ticket?",
        criteria: ["not urgent", "somewhat urgent", "urgent", "critical"]
      },
      churn_risk: {
        type: :noul,
        instructions: "Is the customer likely to cancel or dispute?"
      }
    }
  end

  let(:string_state) { "Hola, quiero cancelar mi pedido [MASK] #4521 ya." }

  let(:string_state_questions) do
    {
      intent: {
        type: :choice,
        instructions: "What does the customer want?",
        criteria: %w[cancel refund track]
      },
      spam: {
        type: :noul,
        instructions: "Is this spam?",
        criteria: {true => "unsolicited advertising", false => "a genuine request"}
      }
    }
  end

  def sequences(state, questions)
    Laya::Questions.normalize_all(questions).to_h do |key, question|
      built = Laya::Sequence.build(tokenizer.method(:encode), tokenizer.special_ids, state, question, max_len: 512, head_max_len: 192)

      [key.to_s, {"ids" => built.ids, "markers" => built.markers}]
    end
  end

  it "resolves the special token ids" do
    expect(tokenizer.special_ids.to_h).to eq(cls: 50281, sep: 50282, mask: 50284, pad: 50283, mask_token: "[MASK]")
  end

  it "encodes a head without special tokens" do
    expect(tokenizer.encode("choice question: Which team should handle this ticket?"))
      .to eq [22122, 1953, 27, 6758, 2285, 943, 6016, 436, 13571, 32]
  end

  it "encodes non-ASCII text and the literal mask token" do
    expect(tokenizer.encode(" 返金 [MASK] ok")).to eq [209, 47397, 38001, 50284, 8718]
  end

  it "encodes an empty string to no ids" do
    expect(tokenizer.encode("")).to eq []
  end

  it "reproduces the reference sequences for the ticket example (267 input tokens)" do
    built = sequences(ticket_state, ticket_questions)

    expect(built).to eq reference["ticket"]
    expect(built.values.sum { |sequence| sequence["ids"].size }).to eq 267
  end

  it "reproduces the reference sequences for a String state, Array choice and custom noul criteria" do
    expect(sequences(string_state, string_state_questions)).to eq reference["string_state"]
  end

  it "raises ModelError when a special token is missing" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "tokenizer"))
      json = JSON.parse(File.read(File.join(FIXTURES, "tokenizer", "tokenizer.json")))
      json["added_tokens"].reject! { |token| token["content"] == "[MASK]" }
      json["model"]["vocab"].delete("[MASK]")
      File.write(File.join(dir, "tokenizer", "tokenizer.json"), JSON.generate(json))

      expect { Laya::Tokenizer.new(dir) }.to raise_error(Laya::ModelError, "special token [MASK] missing from tokenizer")
    end
  end
end
