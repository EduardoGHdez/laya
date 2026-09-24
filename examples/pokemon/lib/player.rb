require "laya"
require_relative "battle_room"
require_relative "challenge"
require_relative "decision"
require_relative "pokedex"
require_relative "random_trainer"
require_relative "request"
require_relative "transcript"

# Plays every battle for one logged-in client. It accepts challenges, keeps a BattleRoom per battle,
# and answers each request with its trainer once that turn's battle log has arrived.
class Player
  FORMAT = "gen9randombattle"

  # Errors about timing rather than the choice itself, which retrying wouldn't fix.
  TIMING_ERRORS = ["too late", "nothing to choose", "crashed"].freeze

  Result = Data.define(:room, :won, :tied, :turns) do
    def outcome
      if tied then "tied"
      elsif won then "won"
      else "lost"
      end
    end
  end

  attr_reader :decisions, :voluntary_switches

  def initialize(client:, trainer:, fallback: RandomTrainer.new, accept_from: nil, max_turns: 300, out: nil, on_finish: nil)
    @client = client
    @trainer = trainer
    @fallback = fallback
    @accept_from = accept_from
    @max_turns = max_turns
    @transcript = Transcript.new(out)
    @on_finish = on_finish
    @rooms = Hash.new { |rooms, id| rooms[id] = BattleRoom.new(id, client.name) }
    @finished = Set.new
    @forfeited = Set.new
    @decisions = 0
    @voluntary_switches = 0
  end

  def switch_rate = @decisions.zero? ? 0 : (100.0 * @voluntary_switches / @decisions).round

  def handle(room_id, lines)
    if room_id.start_with?("battle-")
      play(@rooms[room_id], lines) unless @finished.include?(room_id)
    elsif @accept_from
      lines.filter_map { |line| Challenge.parse(line) }.each { |challenge| answer(challenge) }
    end
  end

  private

  def play(room, lines)
    lines.each do |line|
      if line.start_with?("|request|")
        receive(room, Request.parse(line.delete_prefix("|request|")))
      elsif line.start_with?("|error|[Invalid choice]")
        retry_choice(room, line.delete_prefix("|error|"))
      else
        room.log(line)
      end
    end

    if room.battle.finished? then finish(room)
    elsif room.battle.turn > @max_turns then forfeit(room)
    elsif room.ready? then choose(room, room.pending, decide(room.battle, room.pending))
    end
  end

  def receive(room, request)
    return unless request&.actionable?

    # An update follows a rejected choice, so there is no new log to wait for.
    if request.update?
      choose(room, request, @fallback.decide(room.battle, request))
    else
      room.pending = request
    end
  end

  # Asks the trainer, falling back when Laya fails. Only the trainer's own answers count toward the switch rate.
  def decide(battle, request)
    decision = @trainer.decide(battle, request)
    @decisions += 1
    @voluntary_switches += 1 if decision.voluntary_switch?
    decision
  rescue Laya::Error => e
    warn "  ! Laya failed, choosing at random: #{e.message}"
    @fallback.decide(battle, request)
  end

  def choose(room, request, decision)
    @client.choose(room.id, decision.choice, request.rqid)
    @transcript.decision(room.battle, request, decision)
    room.answered(request)
  end

  # Retries a rejected choice with "default", once per request.
  def retry_choice(room, error)
    warn "  ! #{error}"
    return if TIMING_ERRORS.any? { |text| error.include?(text) }

    request = room.last_request
    choose(room, request, Decision.default) if request && room.first_retry?(request)
  end

  def finish(room)
    @rooms.delete(room.id)
    @finished << room.id
    @client.leave(room.id)
    battle = room.battle
    @on_finish&.call(Result.new(room: room.id, won: battle.won?, tied: battle.winner.nil?, turns: battle.turn))
  end

  def forfeit(room)
    @client.forfeit(room.id) if @forfeited.add?(room.id)
  end

  def answer(challenge)
    return if Pokedex.to_id(challenge.user) == Pokedex.to_id(@client.name)

    if (reason = rejection_reason(challenge))
      # Guests can't send PMs, so the reason only shows in our terminal.
      @client.reject(challenge.user)
      @transcript.rejected(challenge, reason)
    else
      @client.accept(challenge.user)
    end
  end

  def rejection_reason(challenge)
    if challenge.format != FORMAT
      "only #{FORMAT} is supported"
    elsif @accept_from != :anyone && Pokedex.to_id(@accept_from) != Pokedex.to_id(challenge.user)
      "only #{@accept_from} is accepted"
    end
  end
end
