require_relative "decision"
require_relative "pokedex"
require_relative "matchup"

# Asks Laya whether to switch out, which move to use and which Pokémon to bring in, all in one predict call.
class Trainer
  SWITCH_OUT = "Should your active Pokémon switch out this turn instead of attacking?"
  MOVE = "Which move does the most useful damage to the opponent's active Pokémon?"
  SWITCH_TO = "Which Pokémon should come in against the opponent's active Pokémon?"

  def initialize(laya:, pokedex:)
    @laya = laya
    @pokedex = pokedex
  end

  def decide(battle, request)
    moves    = request.moves.to_h { |move| [move.id, move] }
    switches = request.switches.to_h { |pokemon| [Pokedex.to_id(pokemon.species), pokemon] }

    return Decision.default if moves.empty? && switches.empty?

    matchup = Matchup.new(@pokedex, battle, request)
    answers = ask(matchup, moves, switches)

    switch_out = answers[:switch_out]&.noul

    choice = if moves.empty? || switch_out.to_f > 0.5
      "switch #{pick(answers[:switch_to], switches).slot}"
    else
      "move #{pick(answers[:move], moves).slot}"
    end

    Decision.new(
      choice: choice,
      switch_out: switch_out,
      moves: answers[:move]&.probabilities,
      switches: answers[:switch_to]&.probabilities
    )
  end

  private

  # Only asks what's open: whether to switch when both are possible, and which option when there's more than one.
  def ask(matchup, moves, switches)
    questions = {}

    questions[:switch_out] = { type: :noul, instructions: SWITCH_OUT} if moves.any? && switches.any?

    if moves.size > 1
      questions[:move] = {type: :choice, instructions: MOVE,
                          criteria: moves.keys.to_h { |id| [id, matchup.describe_move(id)] }}
    end

    if switches.size > 1
      questions[:switch_to] = {type: :choice, instructions: SWITCH_TO,
                               criteria: switches.transform_values { |pokemon| matchup.describe_switch(pokemon) }}
    end

    questions.empty? ? {} : @laya.predict(matchup.state, questions).answers
  end

  # Laya's pick, or the only option when the question wasn't asked.
  def pick(answer, options) = options.fetch(answer&.choice || options.keys.first)
end
