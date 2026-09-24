# Tallies finished battles and prints the summary at the end of a run.
class Scoreboard
  def initialize(out: $stdout)
    @out = out
    @results = []
  end

  def size = @results.size

  def record(result)
    @results << result
    @out.puts "Battle #{size}: #{result.outcome} in #{result.turns} turns"
  end

  def summary(switch_rate:)
    return "No battles finished." if @results.empty?

    outcomes = @results.map(&:outcome).tally
    won, lost, tied = outcomes.values_at("won", "lost", "tied").map(&:to_i)
    "#{won} won, #{lost} lost, #{tied} tied (#{(100.0 * won / size).round}% win rate), " \
      "#{(@results.sum(&:turns).to_f / size).round(1)} turns on average, " \
      "Laya switched out voluntarily in #{switch_rate}% of its decisions."
  end
end
