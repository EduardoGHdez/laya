# Parses a Showdown HP condition like "250/300", "55/100 brn" or "0 fnt" into [hp_percent, status].
# Percentages round up, so a Pokémon with 1 HP left still shows 1%.
module Condition
  module_function

  def parse(text)
    hp, status = text.split(" ", 2)
    current, max = hp.split("/").map(&:to_f)
    percent = max ? (current * 100 / max).ceil : 0
    [percent, (status == "fnt") ? nil : status]
  end
end
