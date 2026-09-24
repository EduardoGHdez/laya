require_relative "../lib/request"
require_relative "../lib/decision"

RSpec.describe Request do
  describe ".parse" do
    it "reads the request's JSON" do
      request = Request.parse(JSON.generate(move_request))
      expect([request.rqid, request.moves.size]).to eq([3, 3])
    end

    it "returns nil for an empty or null request" do
      expect(Request.parse("")).to be_nil
      expect(Request.parse("null")).to be_nil
    end
  end

  it "isn't actionable while waiting or in team preview" do
    expect(Request.new(move_request)).to be_actionable
    expect(Request.new(move_request.merge("wait" => true))).not_to be_actionable
    expect(Request.new(move_request.merge("teamPreview" => true))).not_to be_actionable
  end

  it "names the move or Pokémon a choice refers to" do
    request = Request.new(move_request)
    expect(request.option_name("move 2")).to eq("dragonclaw")
    expect(request.option_name("switch 3")).to eq("Pikachu")
    expect(request.option_name("default")).to eq("default")
  end

  it "lists usable moves with their /choose slots" do
    request = move_request(moves: [usable("earthquake"), usable("dragonclaw", pp: 0), usable("swordsdance", disabled: true), usable("waterfall")])
    moves = Request.new(request).moves
    expect(moves.map { |move| [move.slot, move.id] }).to eq([[1, "earthquake"], [4, "waterfall"]])
  end

  it "keeps a locked move that has no pp field" do
    request = move_request(moves: [{"move" => "Outrage", "id" => "outrage"}], trapped: true)
    expect(Request.new(request).moves.map(&:id)).to eq(["outrage"])
  end

  it "lists the healthy bench, skipping the active and fainted Pokémon" do
    bench = Request.new(move_request).bench
    expect(bench.map { |pokemon| [pokemon.slot, pokemon.species, pokemon.hp] }).to eq([[2, "Gyarados", 80], [3, "Pikachu", 43]])
  end

  it "reads the active Pokémon" do
    active = Request.new(move_request).active
    expect([active.species, active.hp, active.status, active.moves]).to eq(["Garchomp", 64, "brn", %w[earthquake dragonclaw swordsdance]])
  end

  it "counts the Pokémon left" do
    expect(Request.new(move_request).remaining).to eq(3)
  end

  it "can switch unless trapped" do
    expect(Request.new(move_request)).to be_can_switch
    expect(Request.new(move_request(trapped: true))).not_to be_can_switch
  end

  it "offers no moves on a forced switch" do
    options = Request.new(switch_request)
    expect(options).to be_force_switch
    expect(options.moves).to be_empty
    expect(options).to be_can_switch
  end

  it "picks the healthy bench to switch to on an ordinary forced switch" do
    options = Request.new(switch_request)
    expect(options.switches.map(&:slot)).to eq([2, 3])
  end

  it "picks a fainted Pokémon to revive when Revival Blessing forces the switch" do
    pokemon = team.dup
    pokemon[0] = pokemon_entry("Garchomp, L78, F", "160/250 brn", active: true, moves: %w[revivalblessing])
    pokemon[0]["reviving"] = true
    options = Request.new(switch_request(pokemon:))
    expect(options.switches.map { |pokemon| [pokemon.slot, pokemon.species] }).to eq([[4, "Snorlax"]])
  end
end

RSpec.describe Condition do
  it "parses HP as a rounded-up percentage and the status" do
    expect(Condition.parse("160/250 brn")).to eq([64, "brn"])
    expect(Condition.parse("1/300")).to eq([1, nil])
    expect(Condition.parse("0 fnt")).to eq([0, nil])
  end
end

RSpec.describe Decision do
  it "knows whether it switches" do
    expect(Decision.new(choice: "switch 3")).to be_switch
    expect(Decision.new(choice: "move 1")).not_to be_switch
  end

  it "knows whether a switch was chosen over attacking" do
    expect(Decision.new(choice: "switch 3", switch_out: 0.8)).to be_voluntary_switch
    expect(Decision.new(choice: "switch 3")).not_to be_voluntary_switch
    expect(Decision.new(choice: "move 1", switch_out: 0.2)).not_to be_voluntary_switch
  end
end
