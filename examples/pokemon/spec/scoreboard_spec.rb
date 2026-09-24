require "stringio"
require_relative "../lib/player"
require_relative "../lib/scoreboard"

RSpec.describe Scoreboard do
  let(:out) { StringIO.new }

  subject(:scoreboard) { Scoreboard.new(out:) }

  def result(won: false, tied: false, turns: 10) = Player::Result.new(room: "battle-1", won:, tied:, turns:)

  it "prints each battle as it's recorded" do
    scoreboard.record(result(won: true, turns: 31))
    scoreboard.record(result(tied: true, turns: 12))
    expect(out.string).to eq("Battle 1: won in 31 turns\nBattle 2: tied in 12 turns\n")
    expect(scoreboard.size).to eq(2)
  end

  it "summarizes the run" do
    scoreboard.record(result(won: true, turns: 30))
    scoreboard.record(result(won: true, turns: 35))
    scoreboard.record(result(turns: 40))
    expect(scoreboard.summary(switch_rate: 12)).to eq(
      "2 won, 1 lost, 0 tied (67% win rate), 35.0 turns on average, Laya switched out voluntarily in 12% of its decisions."
    )
  end

  it "says when no battles finished" do
    expect(scoreboard.summary(switch_rate: 0)).to eq("No battles finished.")
  end
end
