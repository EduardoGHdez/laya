require_relative "../lib/pokedex"

RSpec.describe Pokedex do
  subject(:pokedex) { Pokedex.load(File.expand_path("fixtures/pokedex.json", __dir__)) }

  describe "#effectiveness" do
    it "multiplies across both defending types" do
      expect(pokedex.effectiveness("Electric", ["Water", "Flying"])).to eq(4)
      expect(pokedex.effectiveness("Water", ["Water", "Dragon"])).to eq(0.25)
    end

    it "returns 0 for an immunity" do
      expect(pokedex.effectiveness("Ground", ["Water", "Flying"])).to eq(0)
    end

    it "cancels out to 1x" do
      expect(pokedex.effectiveness("Electric", ["Water", "Dragon"])).to eq(1)
    end

    it "is 1x against no known types" do
      expect(pokedex.effectiveness("Ground", [])).to eq(1)
    end
  end

  describe "#types" do
    it "looks up species by their Showdown id" do
      expect(pokedex.types("Rotom-Wash")).to eq(["Electric", "Water"])
    end

    it "returns no types for an unknown species" do
      expect(pokedex.types("Missingno")).to eq([])
    end
  end

  describe "#move" do
    it "returns the move's facts" do
      move = pokedex.move("dragonclaw")
      expect([move.name, move.type, move.category, move.base_power]).to eq(["Dragon Claw", "Dragon", "Physical", 80])
      expect(move).not_to be_status
    end

    it "flags status moves" do
      expect(pokedex.move("swordsdance")).to be_status
    end

    it "drops the numeric suffix request ids can carry" do
      expect(pokedex.move("return102").id).to eq("return")
    end

    it "returns nil for an unknown move" do
      expect(pokedex.move("notamove")).to be_nil
    end
  end

  describe ".describe_effectiveness" do
    it "words each multiplier" do
      expect(Pokedex.describe_effectiveness(0)).to eq("no effect (0x)")
      expect(Pokedex.describe_effectiveness(0.25)).to eq("not very effective (0.25x)")
      expect(Pokedex.describe_effectiveness(1.0)).to eq("neutral (1x)")
      expect(Pokedex.describe_effectiveness(4)).to eq("super effective (4x)")
    end
  end
end
