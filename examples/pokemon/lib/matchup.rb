require_relative "pokedex"

# Describes the battle to Laya from our side, using facts from the pokedex: the state text, and each
# move or switch measured against the opponent's active Pokémon.
class Matchup
  STATUSES = {"brn" => "burned", "par" => "paralyzed", "slp" => "asleep", "frz" => "frozen",
              "psn" => "poisoned", "tox" => "badly poisoned"}.freeze

  def initialize(pokedex, battle, request)
    @pokedex = pokedex
    @battle = battle
    @request = request
    @opponent = battle.opponent_active
    @opponent_types = @opponent ? pokedex.types(@opponent.species) : []
  end

  def state
    own = @request.active
    [
      "Turn #{@battle.turn}.",
      "Your #{describe_active(own)}.",
      ("The opponent's #{describe_active(@opponent)}." if @opponent),
      (threat(own) if @opponent_types.any?),
      "You have #{@request.remaining} Pokémon left, the opponent has #{@battle.opponent_remaining}."
    ].compact.join(" ")
  end

  def describe_move(id)
    move = @pokedex.move(id)
    return "" unless move
    return "status: #{move.short_desc}" if move.status?

    power = move.base_power.positive? ? "#{move.base_power} power" : "variable power"
    effect = Pokedex.describe_effectiveness(@pokedex.effectiveness(move.type, @opponent_types))
    "#{move.type}, #{move.category.downcase}, #{power}, #{effect}"
  end

  def describe_switch(pokemon)
    types = @pokedex.types(pokemon.species)
    takes = strongest_type(types)&.last || 1
    best = best_hit(pokemon.moves)
    hits = best ? "hits it #{Pokedex.format_multiplier(best)}" : "has no damaging moves"
    "#{types.join("/")}, #{pokemon.hp}% HP, takes #{Pokedex.format_multiplier(takes)} from its types, #{hits}"
  end

  private

  def describe_active(pokemon)
    status = STATUSES.key?(pokemon.status) ? " and #{STATUSES[pokemon.status]}" : ""
    "#{pokemon.species} (#{@pokedex.types(pokemon.species).join("/")}) is at #{pokemon.hp}% HP#{status}"
  end

  def threat(own)
    threat_type, multiplier = strongest_type(@pokedex.types(own.species))
    best = best_hit(own.moves)
    ours = best ? "your best move hits it #{Pokedex.format_multiplier(best)}" : "you have no damaging moves"
    "The opponent's #{threat_type} attacks hit you #{Pokedex.format_multiplier(multiplier)}, and #{ours}."
  end

  # The opponent's type that hits the defender hardest, as [type, multiplier], or nil when its types are unknown.
  def strongest_type(defender_types)
    @opponent_types.map { |type| [type, @pokedex.effectiveness(type, defender_types)] }.max_by(&:last)
  end

  # The best multiplier among the damaging moves against the opponent, or nil when there are none.
  def best_hit(move_ids)
    move_ids.filter_map { |id| @pokedex.move(id) }.reject(&:status?)
      .map { |move| @pokedex.effectiveness(move.type, @opponent_types) }.max
  end
end
