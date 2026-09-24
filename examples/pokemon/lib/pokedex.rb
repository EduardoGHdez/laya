require "json"

# Move, species and type data exported from Showdown by export_dex.js.
class Pokedex
  DEFAULT_PATH = File.expand_path("../vendor/pokedex.json", __dir__)

  Move = Data.define(:id, :name, :type, :category, :base_power, :short_desc) do
    def status? = category == "Status"
  end

  def self.load(path = DEFAULT_PATH) = new(JSON.parse(File.read(path)))

  # Showdown ids are lowercase alphanumerics: "Rotom-Wash" → "rotomwash".
  def self.to_id(name) = name.to_s.downcase.gsub(/[^a-z0-9]/, "")

  def self.format_multiplier(value) = "#{(value == value.to_i) ? value.to_i : value}x"

  def self.describe_effectiveness(value)
    word = if value.zero? then "no effect"
    elsif value < 1 then "not very effective"
    elsif value > 1 then "super effective"
    else "neutral"
    end
    "#{word} (#{format_multiplier(value)})"
  end

  def initialize(data)
    @moves = data.fetch("moves")
    @species = data.fetch("species")
    @effectiveness = data.fetch("effectiveness")
  end

  # Request move ids can carry a numeric suffix, like "return102" (Return at 102 power).
  def move(id)
    id = Pokedex.to_id(id)
    key = [id, id.sub(/\d+\z/, "")].find { |candidate| @moves.key?(candidate) }
    return unless key

    move = @moves.fetch(key)
    Move.new(id: key, name: move["name"], type: move["type"], category: move["category"],
      base_power: move["basePower"], short_desc: move["shortDesc"])
  end

  def types(species) = @species.dig(Pokedex.to_id(species), "types") || []

  def effectiveness(move_type, defender_types)
    chart = @effectiveness.fetch(move_type, {})
    defender_types.reduce(1) { |total, type| total * chart.fetch(type, 1) }
  end
end
