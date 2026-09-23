RSpec.describe "Laya against the reference output", :model do
  # Loading the 1.7 GB model takes seconds, so every example shares one answer
  before(:context) { @result = Laya.new(model_dir: ENV.fetch("LAYA_MODEL_DIR")).system_one(state, questions) }

  let(:result) { @result }

  def state
    {
      subject: "Refund not received",
      body: "I cancelled my subscription two weeks ago and I still have not received my refund. " \
        "This is the third time I am writing. If this is not resolved I will dispute the charge with my bank."
    }
  end

  def questions
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

  it "counts the same input tokens" do
    expect(result.usage.input_tokens).to eq 267
  end

  it "reproduces the choice answer" do
    expect(result[:department].choice).to eq "billing"
    expect(result[:department].probabilities).to eq({"billing" => 0.9415, "support" => 0.031, "sales" => 0.0275})
    expect(result[:department].confidence).to eq 0.7603
  end

  it "reproduces the score answer" do
    expect(result[:urgency].score).to eq 1.3886
    expect(result[:urgency].probabilities).to eq({"0" => 0.1752, "1" => 0.2947, "2" => 0.4962, "3" => 0.0338})
  end

  it "reproduces the noul answer" do
    expect(result[:churn_risk].noul).to eq 0.0988
  end

  it "returns act probabilities between 0 and 1" do
    expect(result.answers.values.map(&:act_probability)).to all(be_between(0.0, 1.0))
  end
end
