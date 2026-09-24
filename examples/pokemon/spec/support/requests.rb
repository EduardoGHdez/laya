# Builders for Showdown request hashes, shaped like the JSON after "|request|".
module Requests
  def pokemon_entry(details, condition, active: false, moves: [])
    {"ident" => "p1: #{details.split(",").first}", "details" => details, "condition" => condition,
     "active" => active, "moves" => moves}
  end

  def team
    [
      pokemon_entry("Garchomp, L78, F", "160/250 brn", active: true, moves: %w[earthquake dragonclaw swordsdance]),
      pokemon_entry("Gyarados, L80, M", "240/300", moves: %w[waterfall]),
      pokemon_entry("Pikachu, L90, F", "90/211", moves: %w[thunderbolt]),
      pokemon_entry("Snorlax, L80, M", "0 fnt", moves: %w[return102])
    ]
  end

  def usable(id, pp: 10, disabled: false) = {"move" => id, "id" => id, "pp" => pp, "maxpp" => 10, "disabled" => disabled}

  def move_request(moves: %w[earthquake dragonclaw swordsdance].map { |id| usable(id) }, pokemon: team, trapped: false)
    active = {"moves" => moves}
    active["trapped"] = true if trapped
    {"active" => [active], "side" => {"name" => "LayaBot", "id" => "p1", "pokemon" => pokemon}, "rqid" => 3}
  end

  def switch_request(pokemon: team)
    {"forceSwitch" => [true], "side" => {"name" => "LayaBot", "id" => "p1", "pokemon" => pokemon}, "rqid" => 4}
  end
end

RSpec.configure { |config| config.include Requests }
