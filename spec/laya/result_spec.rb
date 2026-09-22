RSpec.describe Laya::Result do
  let(:choice_answer) do
    Laya::ChoiceAnswer.new(
      choice: "billing",
      probabilities: {"billing" => 0.9, "sales" => 0.1},
      confidence: 0.53,
      act_probability: 0.8
    )
  end

  let(:score_answer) do
    Laya::ScoreAnswer.new(
      score: 1.2,
      probabilities: {"0" => 0.3, "1" => 0.2, "2" => 0.5},
      legend: {"0" => "low", "1" => "mid", "2" => "high"},
      confidence: 0.1,
      act_probability: 0.6
    )
  end

  let(:noul_answer) { Laya::NoulAnswer.new(noul: 0.09, act_probability: 0.3) }

  let(:result) do
    Laya::Result.new(
      model: "laya",
      answers: {department: choice_answer, urgency: score_answer, churn: noul_answer},
      usage: Laya::Usage.new(input_tokens: 42, output_tokens: 0)
    )
  end

  it "reads an answer by key" do
    expect(result[:department].choice).to eq "billing"
  end

  it "reads answers through #answers" do
    expect(result.answers[:urgency].score).to eq 1.2
  end

  it "returns nil for an unknown key" do
    expect(result[:missing]).to be_nil
  end

  it "tags each answer with its type" do
    expect(choice_answer.type).to eq "choice"
    expect(score_answer.type).to eq "score"
    expect(noul_answer.type).to eq "noul"
  end

  it "converts a choice answer to Hash" do
    expect(choice_answer.to_h).to eq(
      type: "choice",
      choice: "billing",
      probabilities: {"billing" => 0.9, "sales" => 0.1},
      confidence: 0.53,
      rl_agent: {act_probability: 0.8}
    )
  end

  it "converts a score answer to Hash" do
    expect(score_answer.to_h).to eq(
      type: "score",
      score: 1.2,
      legend: {"0" => "low", "1" => "mid", "2" => "high"},
      probabilities: {"0" => 0.3, "1" => 0.2, "2" => 0.5},
      confidence: 0.1,
      rl_agent: {act_probability: 0.6}
    )
  end

  it "converts a noul answer to Hash" do
    expect(noul_answer.to_h).to eq(
      type: "noul",
      noul: 0.09,
      rl_agent: {act_probability: 0.3}
    )
  end

  it "converts the whole result to Hash" do
    expect(result.to_h).to eq(
      model: "laya",
      answers: {
        department: choice_answer.to_h,
        urgency: score_answer.to_h,
        churn: noul_answer.to_h
      },
      usage: {input_tokens: 42, output_tokens: 0}
    )
  end
end
