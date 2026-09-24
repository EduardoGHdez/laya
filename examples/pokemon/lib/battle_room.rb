require_relative "battle"

# One battle a player is in: its state, the request waiting for an answer, and how much of the turn's log has arrived.
class BattleRoom
  attr_reader :battle, :last_request
  attr_accessor :pending

  def initialize(id, username)
    @battle = Battle.new(id, username)
    @retried = Set.new
    @log_seen = @turn_seen = false
  end

  def id = battle.room

  def log(line)
    battle.handle(line)
    @log_seen = true
    @turn_seen = true if line.start_with?("|turn|")
  end

  # A request can be answered once the battle it's about is up to date: a forced switch after
  # the log that caused it, any other request once the next turn has started.
  def ready?
    return false unless pending

    pending.force_switch? ? @log_seen : @turn_seen
  end

  def answered(request)
    @last_request = request
    @pending = nil
    @log_seen = @turn_seen = false
  end

  # True only the first time it's asked about a request, so a rejected choice is retried once.
  def first_retry?(request) = !@retried.add?(request.rqid).nil?
end
