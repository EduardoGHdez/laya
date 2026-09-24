require "stringio"
require_relative "../lib/player"
require_relative "../lib/showdown_client"

# Stands in for the WebSocket, recording what the client sends as [room, text].
class FakeConnection
  attr_reader :sent

  def initialize
    @sent = []
  end

  def send_text(message) = @sent << message.split("|", 2)

  def flush = nil
end

class FixedTrainer
  def initialize(decision)
    @decision = decision
  end

  def decide(_battle, _request) = @decision
end

class FailingTrainer
  def decide(_battle, _request) = raise(Laya::InvalidQuestionError, "bad question")
end

RSpec.describe Player do
  let(:room) { "battle-gen9randombattle-1" }
  let(:connection) { FakeConnection.new }
  let(:client) { ShowdownClient.new(connection, "LayaBot") }
  let(:trainer) { FixedTrainer.new(Decision.new(choice: "move 2")) }
  let(:fallback) { FixedTrainer.new(Decision.new(choice: "move 1")) }
  let(:results) { [] }
  let(:out) { StringIO.new }
  let(:options) { {} }

  subject(:player) do
    Player.new(client:, trainer:, fallback:, out:, on_finish: ->(result) { results << result }, **options)
  end

  def request_line(request) = "|request|#{JSON.generate(request)}"

  let(:start_log) do
    ["|player|p1|LayaBot|1|", "|switch|p1a: Garchomp|Garchomp, L78, F|160/250 brn",
      "|switch|p2a: Rotom|Rotom-Wash, L86|100/100", "|turn|1"]
  end

  def choices = connection.sent.select { |_room, text| text.start_with?("/choose") }

  it "waits for the turn's log before answering a request" do
    player.handle(room, [request_line(move_request)])
    expect(choices).to be_empty

    player.handle(room, start_log)
    expect(choices).to eq([[room, "/choose move 2|3"]])
  end

  it "answers when the request arrives after the log" do
    player.handle(room, start_log)
    player.handle(room, [request_line(move_request)])
    expect(choices).to eq([[room, "/choose move 2|3"]])
  end

  it "answers a forced switch as soon as its request arrives, since the real server sends the log first" do
    player = Player.new(client:, trainer: FixedTrainer.new(Decision.new(choice: "switch 2")))
    player.handle(room, start_log)
    player.handle(room, [request_line(move_request)])
    expect(choices.size).to eq(1)

    player.handle(room, ["|-damage|p1a: Garchomp|0 fnt", "|faint|p1a: Garchomp", "|upkeep"])
    player.handle(room, [request_line(switch_request)])
    expect(choices.last).to eq([room, "/choose switch 2|4"])
  end

  it "still answers a forced switch once its log frame arrives, defensively, if the request comes first" do
    player.handle(room, start_log)
    player.handle(room, [request_line(move_request)])
    player.handle(room, [request_line(switch_request)])
    expect(choices.size).to eq(1)

    player.handle(room, ["|-damage|p1a: Garchomp|0 fnt", "|faint|p1a: Garchomp", "|upkeep"])
    expect(choices.last).to eq([room, "/choose move 2|4"])
  end

  it "ignores wait requests" do
    player.handle(room, start_log)
    player.handle(room, [request_line({"wait" => true, "side" => {"pokemon" => []}, "rqid" => 5})])
    expect(choices).to be_empty
  end

  it "ignores a null request" do
    player.handle(room, start_log)
    player.handle(room, ["|request|null"])
    expect(choices).to be_empty
  end

  it "answers a rejected choice with default" do
    player.handle(room, [request_line(move_request)])
    player.handle(room, start_log)
    player.handle(room, ["|error|[Invalid choice] Can't move: Garchomp's Dragon Claw is disabled"])
    expect(choices).to eq([[room, "/choose move 2|3"], [room, "/choose default|3"]])
  end

  it "doesn't count a retry as a decision" do
    player.handle(room, [request_line(move_request)])
    player.handle(room, start_log)
    player.handle(room, ["|error|[Invalid choice] Can't move: Garchomp's Dragon Claw is disabled"])
    expect(player.decisions).to eq(1)
  end

  it "retries a rejected choice only once per request" do
    player.handle(room, [request_line(move_request)])
    player.handle(room, start_log)
    player.handle(room, ["|error|[Invalid choice] Can't move: Garchomp's Dragon Claw is disabled"])
    player.handle(room, ["|error|[Invalid choice] Can't move: Garchomp's Dragon Claw is disabled"])
    expect(choices).to eq([[room, "/choose move 2|3"], [room, "/choose default|3"]])
  end

  it "only logs an error about timing rather than the choice" do
    player.handle(room, [request_line(move_request)])
    player.handle(room, start_log)
    expect {
      player.handle(room, ["|error|[Invalid choice] Sorry, too late to make a different move; the next turn has already started"])
    }.to output(/too late/).to_stderr
    expect(choices).to eq([[room, "/choose move 2|3"]])
  end

  it "answers an update request with the fallback trainer right away" do
    player.handle(room, [request_line(move_request.merge("update" => true, "rqid" => 6))])
    expect(choices).to eq([[room, "/choose move 1|6"]])
  end

  it "doesn't count an update request as a decision" do
    player.handle(room, [request_line(move_request.merge("update" => true, "rqid" => 6))])
    expect(player.decisions).to eq(0)
  end

  context "when the trainer raises a Laya error" do
    let(:trainer) { FailingTrainer.new }

    it "uses the fallback trainer" do
      player.handle(room, [request_line(move_request)])
      expect { player.handle(room, start_log) }.to output(/bad question/).to_stderr
      expect(choices).to eq([[room, "/choose move 1|3"]])
    end

    it "doesn't count the fallback answer as a decision" do
      player.handle(room, [request_line(move_request)])
      expect { player.handle(room, start_log) }.to output(/bad question/).to_stderr
      expect(player.decisions).to eq(0)
    end
  end

  it "reports the result and leaves the room when the battle ends" do
    player.handle(room, start_log)
    player.handle(room, ["|win|LayaBot"])
    expect(results).to eq([Player::Result.new(room:, won: true, tied: false, turns: 1)])
    expect(connection.sent.last).to eq([room, "/leave"])

    player.handle(room, ["|deinit"])
    expect(results.size).to eq(1)
  end

  it "reports a tie" do
    player.handle(room, start_log)
    player.handle(room, ["|tie"])
    expect(results).to eq([Player::Result.new(room:, won: false, tied: true, turns: 1)])
  end

  context "with a turn cap" do
    let(:options) { {max_turns: 1} }

    it "forfeits once the cap is passed" do
      player.handle(room, start_log + ["|turn|2"])
      player.handle(room, ["|turn|3"])
      expect(connection.sent.count { |_room, text| text == "/forfeit" }).to eq(1)
      expect(choices).to be_empty
    end
  end

  it "prints each decision" do
    player = Player.new(client:, trainer: FixedTrainer.new(Decision.new(choice: "move 2", switch_out: 0.23,
      moves: {"earthquake" => 0.3, "dragonclaw" => 0.7})), out:)
    player.handle(room, start_log + [request_line(move_request)])
    expect(out.string).to eq(<<~TEXT)
      Turn 1  Garchomp 64% brn  vs  Rotom-Wash 100%
        switch out?  0.23
        moves   dragonclaw 0.70 · earthquake 0.30
        → dragonclaw
    TEXT
  end

  it "counts voluntary switches" do
    player = Player.new(client:, trainer: FixedTrainer.new(Decision.new(choice: "switch 2", switch_out: 0.8)))
    player.handle(room, start_log + [request_line(move_request)])
    expect([player.decisions, player.voluntary_switches, player.switch_rate]).to eq([1, 1, 100])
  end

  describe "challenges" do
    let(:options) { {accept_from: :anyone} }

    def challenge(format, from: " RandomBot") = "|pm|#{from}| LayaBot|/challenge #{format}|#{format}|||"

    it "accepts Gen 9 Random Battle from anyone" do
      player.handle("", [challenge("gen9randombattle")])
      expect(connection.sent).to eq([["", "/utm null"], ["", "/accept RandomBot"]])
    end

    it "rejects other formats and says why in the terminal" do
      player.handle("", [challenge("gen9ou", from: "+Ash@!")])
      expect(connection.sent).to eq([["", "/reject Ash"]])
      expect(out.string).to eq("Rejected Ash's challenge: only gen9randombattle is supported.\n")
    end

    it "ignores its own challenges and cancellations" do
      player.handle("", [challenge("gen9randombattle", from: " LayaBot"), "|pm| RandomBot| LayaBot|/challenge"])
      expect(connection.sent).to be_empty
    end

    context "when not accepting challenges" do
      let(:options) { {} }

      it "ignores them" do
        player.handle("", [challenge("gen9randombattle")])
        expect(connection.sent).to be_empty
      end
    end

    context "in headless mode, accepting only from RandomBot" do
      let(:options) { {accept_from: "RandomBot"} }

      it "accepts RandomBot's challenge" do
        player.handle("", [challenge("gen9randombattle")])
        expect(connection.sent).to eq([["", "/utm null"], ["", "/accept RandomBot"]])
      end

      it "rejects a challenge from anyone else and says why in the terminal" do
        player.handle("", [challenge("gen9randombattle", from: "+Ash@!")])
        expect(connection.sent).to eq([["", "/reject Ash"]])
        expect(out.string).to eq("Rejected Ash's challenge: only RandomBot is accepted.\n")
      end
    end
  end
end

RSpec.describe Player::Result do
  it "names the outcome" do
    expect(Player::Result.new(room: "r", won: true, tied: false, turns: 1).outcome).to eq("won")
    expect(Player::Result.new(room: "r", won: false, tied: false, turns: 1).outcome).to eq("lost")
    expect(Player::Result.new(room: "r", won: false, tied: true, turns: 1).outcome).to eq("tied")
  end
end
