require_relative "../lib/battle"
require_relative "../lib/pokedex"
require_relative "../lib/request"
require_relative "../lib/trainer"

# Records every predict call and answers the questions asked from canned answers.
class StubLaya
  attr_reader :calls

  def initialize(answers)
    @answers = answers
    @calls = []
  end

  def predict(state, questions)
    @calls << [state, questions]
    Laya::Result.new(model: "stub", answers: @answers.slice(*questions.keys), usage: nil)
  end
end

RSpec.describe Trainer do
  let(:pokedex) { Pokedex.load(File.expand_path("fixtures/pokedex.json", __dir__)) }
  let(:battle) do
    Battle.new("battle-gen9randombattle-1", "LayaBot").tap do |battle|
      ["|player|p1|LayaBot|1|", "|switch|p1a: Garchomp|Garchomp, L78, F|160/250 brn",
        "|switch|p2a: Rotom|Rotom-Wash, L86|100/100", "|turn|7"].each { |line| battle.handle(line) }
    end
  end

  def noul(value) = Laya::NoulAnswer.new(noul: value, act_probability: nil)

  def choice(label, probabilities) = Laya::ChoiceAnswer.new(choice: label, probabilities:, confidence: nil, act_probability: nil)

  let(:move_probabilities) { {"earthquake" => 0.7, "dragonclaw" => 0.2, "swordsdance" => 0.1} }
  let(:switch_probabilities) { {"gyarados" => 0.3, "pikachu" => 0.7} }
  let(:answers) do
    {switch_out: noul(0.2), move: choice("earthquake", move_probabilities), switch_to: choice("pikachu", switch_probabilities)}
  end
  let(:laya) { StubLaya.new(answers) }

  subject(:trainer) { Trainer.new(laya:, pokedex:) }

  it "describes the matchup in the state" do
    trainer.decide(battle, Request.new(move_request))
    expect(laya.calls.first[0]).to eq(
      "Turn 7. Your Garchomp (Dragon/Ground) is at 64% HP and burned. " \
      "The opponent's Rotom-Wash (Electric/Water) is at 100% HP. " \
      "The opponent's Water attacks hit you 1x, and your best move hits it 2x. " \
      "You have 3 Pokémon left, the opponent has 6."
    )
  end

  it "asks all three questions in one call on a normal turn" do
    trainer.decide(battle, Request.new(move_request))
    expect(laya.calls.size).to eq(1)
    questions = laya.calls.first[1]
    expect(questions[:switch_out]).to eq(type: :noul, instructions: Trainer::SWITCH_OUT)
    expect(questions[:move]).to eq(type: :choice, instructions: Trainer::MOVE, criteria: {
      "earthquake" => "Ground, physical, 100 power, super effective (2x)",
      "dragonclaw" => "Dragon, physical, 80 power, neutral (1x)",
      "swordsdance" => "status: Raises the user's Attack by 2."
    })
    expect(questions[:switch_to]).to eq(type: :choice, instructions: Trainer::SWITCH_TO, criteria: {
      "gyarados" => "Water/Flying, 80% HP, takes 4x from its types, hits it 0.5x",
      "pikachu" => "Electric, 43% HP, takes 1x from its types, hits it 1x"
    })
  end

  it "uses the top move when switching out is unlikely" do
    decision = trainer.decide(battle, Request.new(move_request))
    expect(decision).to eq(Decision.new(choice: "move 1", switch_out: 0.2, moves: move_probabilities, switches: switch_probabilities))
  end

  it "switches to the top Pokémon when switching out is likely" do
    answers[:switch_out] = noul(0.7)
    expect(trainer.decide(battle, Request.new(move_request)).choice).to eq("switch 3")
  end

  it "only asks which Pokémon to bring in on a forced switch" do
    decision = trainer.decide(battle, Request.new(switch_request))
    expect(laya.calls.first[1].keys).to eq([:switch_to])
    expect(decision.choice).to eq("switch 3")
  end

  it "only asks which move to use when trapped" do
    decision = trainer.decide(battle, Request.new(move_request(trapped: true)))
    expect(laya.calls.first[1].keys).to eq([:move])
    expect(decision).to eq(Decision.new(choice: "move 1", moves: move_probabilities))
  end

  it "skips predict when there is only one option" do
    request = move_request(moves: [{"move" => "Outrage", "id" => "outrage"}], trapped: true)
    expect(trainer.decide(battle, Request.new(request)).choice).to eq("move 1")
    expect(laya.calls).to be_empty
  end

  it "takes the only switch without asking" do
    pokemon = [pokemon_entry("Garchomp, L78, F", "0 fnt", active: true), pokemon_entry("Gyarados, L80, M", "240/300", moves: %w[waterfall])]
    expect(trainer.decide(battle, Request.new(switch_request(pokemon:))).choice).to eq("switch 2")
    expect(laya.calls).to be_empty
  end

  it "says so when the active Pokémon has no damaging moves" do
    pokemon = team.dup
    pokemon[0] = pokemon_entry("Garchomp, L78, F", "160/250 brn", active: true, moves: %w[swordsdance])
    trainer.decide(battle, Request.new(move_request(moves: [usable("swordsdance"), usable("dragonclaw", pp: 0)], pokemon:)))
    expect(laya.calls.first[0]).to include("and you have no damaging moves.")
  end
end
