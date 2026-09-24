require_relative "../lib/random_trainer"
require_relative "../lib/request"

RSpec.describe RandomTrainer do
  subject(:trainer) { RandomTrainer.new(random: Random.new(1)) }

  def choices(request) = Array.new(50) { trainer.decide(nil, Request.new(request)).choice }.uniq.sort

  it "picks among usable moves and the healthy bench" do
    expect(choices(move_request)).to eq(["move 1", "move 2", "move 3", "switch 2", "switch 3"])
  end

  it "only switches on a forced switch" do
    expect(choices(switch_request)).to eq(["switch 2", "switch 3"])
  end

  it "only offers fainted Pokémon to revive when Revival Blessing forces the switch" do
    pokemon = team.dup
    pokemon[0] = pokemon_entry("Garchomp, L78, F", "160/250 brn", active: true, moves: %w[revivalblessing])
    pokemon[0]["reviving"] = true
    expect(choices(switch_request(pokemon:))).to eq(["switch 4"])
  end

  it "only uses moves when trapped" do
    expect(choices(move_request(trapped: true))).to eq(["move 1", "move 2", "move 3"])
  end

  it "falls back to default when nothing is listed" do
    request = move_request(moves: [], pokemon: [pokemon_entry("Garchomp, L78, F", "100/250", active: true)])
    expect(trainer.decide(nil, Request.new(request)).choice).to eq("default")
  end
end
