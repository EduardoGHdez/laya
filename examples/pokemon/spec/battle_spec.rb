require_relative "../lib/battle"

RSpec.describe Battle do
  let(:lines) { File.readlines(File.expand_path("fixtures/battle.log", __dir__), chomp: true) }

  def play(lines, username: "LayaBot")
    Battle.new("battle-gen9randombattle-1", username).tap do |battle|
      lines.each { |line| battle.handle(line) }
    end
  end

  it "finds our side from the player lines" do
    expect(play(lines.first(2)).side).to eq("p1")
    expect(play(lines.first(2), username: "RandomBot").side).to eq("p2")
  end

  it "tracks both actives through a turn" do
    battle = play(lines.take_while { |line| line != "|turn|2" })
    expect(battle.own_active).to eq(Battle::Pokemon.new(species: "Garchomp", hp: 88, status: "brn"))
    expect(battle.opponent_active).to eq(Battle::Pokemon.new(species: "Rotom-Wash", hp: 100, status: nil))
    expect(battle.turn).to eq(1)
  end

  it "ignores status changes on benched Pokémon" do
    battle = play(lines.take_while { |line| line != "|turn|3" })
    expect(battle.own_active.status).to eq("brn")
  end

  it "counts faints and the winner" do
    battle = play(lines)
    expect(battle.fainted).to eq("p1" => 1, "p2" => 1)
    expect(battle.own_active).to eq(Battle::Pokemon.new(species: "Gyarados", hp: 100, status: nil))
    expect(battle.opponent_active.hp).to eq(0)
    expect(battle.turn).to eq(4)
    expect(battle).to be_finished
    expect(battle).to be_won
  end

  it "follows Illusion ending and forme changes" do
    # "replace" carries no HP field; the opponent's HP must be unchanged.
    battle = play(lines.first(10) + ["|replace|p2a: Zoroark|Zoroark-Hisui, L79, M",
      "|-formechange|p1a: Garchomp|Garchomp-Mega|[msg]"])
    expect(battle.opponent_active.species).to eq("Zoroark-Hisui")
    expect(battle.opponent_active.hp).to eq(100)
    expect(battle.own_active).to eq(Battle::Pokemon.new(species: "Garchomp-Mega", hp: 100, status: nil))
  end

  it "is lost when the other player wins" do
    expect(play(lines, username: "RandomBot")).not_to be_won
  end

  it "finishes without a winner on a tie" do
    battle = play(lines.first(10) + ["|tie"])
    expect(battle).to be_finished
    expect(battle).not_to be_won
  end
end
