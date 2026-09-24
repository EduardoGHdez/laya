# Prints each decision and rejected challenge for someone watching the terminal. Prints nothing without an output.
class Transcript
  def initialize(out)
    @out = out
  end

  def decision(battle, request, decision)
    return unless @out

    @out.puts "Turn #{battle.turn}  #{describe(request.active)}  vs  #{describe(battle.opponent_active)}"
    @out.puts "  switch out?  #{format("%.2f", decision.switch_out)}" if decision.switch_out
    @out.puts "  moves   #{probabilities(decision.moves)}" if decision.moves
    @out.puts "  switch  #{probabilities(decision.switches)}" if decision.switches
    @out.puts "  → #{request.option_name(decision.choice)}"
  end

  def rejected(challenge, reason)
    @out&.puts "Rejected #{challenge.user}'s challenge: #{reason}."
  end

  private

  def describe(pokemon) = pokemon ? [pokemon.species, "#{pokemon.hp}%", pokemon.status].compact.join(" ") : "?"

  def probabilities(probabilities)
    probabilities.sort_by { |_label, probability| -probability }
      .map { |label, probability| "#{label} #{format("%.2f", probability)}" }
      .join(" · ")
  end
end
