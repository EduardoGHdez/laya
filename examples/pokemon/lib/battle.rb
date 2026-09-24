require_relative "condition"
require_relative "pokedex"

# The state of one battle, updated line by line from the room's protocol messages.
class Battle
  Pokemon = Data.define(:species, :hp, :status)

  # "p2a: Rotom" is an active Pokémon; "p2: Rotom" is on the bench.
  ACTIVE_IDENT = /\Ap\d[a-z]:/

  attr_reader :room, :side, :turn, :winner, :fainted

  def initialize(room, username)
    @room = room
    @userid = Pokedex.to_id(username)
    @side = nil
    @turn = 0
    @winner = nil
    @finished = false
    @active = {}
    @fainted = Hash.new(0)
  end

  def finished? = @finished

  def won? = !winner.nil? && Pokedex.to_id(winner) == @userid

  def opponent_side = (side == "p2") ? "p1" : "p2"

  def own_active = @active[side]

  def opponent_active = @active[opponent_side]

  def opponent_remaining = 6 - fainted[opponent_side]

  def handle(line)
    _, type, *args = line.split("|")
    case type
    when "player"
      @side = args[0] if args[1] && Pokedex.to_id(args[1]) == @userid
    when "switch", "drag"
      hp, status = Condition.parse(args[2])
      @active[args[0][0, 2]] = Pokemon.new(species: args[1].split(",").first, hp:, status:)
    when "replace", "detailschange", "-formechange"
      # "replace" (Illusion ending) has no HP field: it only reveals the real species.
      update(args[0]) { |pokemon| pokemon.with(species: args[1].split(",").first) }
    when "-damage", "-heal", "-sethp"
      hp, status = Condition.parse(args[1])
      update(args[0]) { |pokemon| pokemon.with(hp:, status:) }
    when "-status"
      update(args[0]) { |pokemon| pokemon.with(status: args[1]) }
    when "-curestatus"
      update(args[0]) { |pokemon| pokemon.with(status: nil) }
    when "faint"
      @fainted[args[0][0, 2]] += 1
      update(args[0]) { |pokemon| pokemon.with(hp: 0, status: nil) }
    when "turn"
      @turn = args[0].to_i
    when "win"
      @winner = args[0]
      @finished = true
    when "tie"
      @finished = true
    end
  end

  private

  def update(ident)
    return unless ident.match?(ACTIVE_IDENT)

    key = ident[0, 2]
    @active[key] = yield(@active[key]) if @active[key]
  end
end
