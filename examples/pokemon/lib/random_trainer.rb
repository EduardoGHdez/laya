require_relative "decision"

# Picks uniformly among the legal moves and switches. The fallback when Laya can't answer.
class RandomTrainer
  def initialize(random: Random.new)
    @random = random
  end

  def decide(_battle, request)
    choices = request.moves.map { |move| "move #{move.slot}" } + request.switches.map { |pokemon| "switch #{pokemon.slot}" }
    choices.empty? ? Decision.default : Decision.new(choice: choices.sample(random: @random))
  end
end
