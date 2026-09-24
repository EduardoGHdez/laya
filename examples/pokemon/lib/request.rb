require "json"
require_relative "condition"

# A Showdown request: what the server asks us to choose, with the usable moves and the Pokémon
# a switch can pick, each with its /choose slot.
class Request
  Move = Data.define(:slot, :id)

  Pokemon = Data.define(:slot, :species, :hp, :status, :active, :moves, :reviving) do
    def fainted? = hp.zero?
  end

  # Parses the JSON after "|request|". Returns nil for an empty or null request.
  def self.parse(json)
    data = JSON.parse(json) unless json.empty?
    new(data) if data.is_a?(Hash)
  end

  attr_reader :team

  def initialize(data)
    @data = data
    @team = data.dig("side", "pokemon").to_a.each_with_index.map do |entry, index|
      hp, status = Condition.parse(entry.fetch("condition"))
      Pokemon.new(slot: index + 1, species: species(entry), hp:, status:, active: entry.fetch("active", false),
        moves: entry.fetch("moves", []), reviving: entry.fetch("reviving", false))
    end
  end

  def rqid = @data.fetch("rqid")

  # An update re-asks after a rejected choice, so no new log comes with it.
  def update? = @data.fetch("update", false)

  # Wait and team preview requests don't need a choice.
  def actionable? = !@data["wait"] && !@data["teamPreview"]

  def force_switch? = Array(@data["forceSwitch"]).first == true

  def trapped? = active_slot.fetch("trapped", false)

  def can_switch? = !trapped? && bench.any?

  def active = team.find(&:active)

  def bench = team.reject { |pokemon| pokemon.active || pokemon.fainted? }

  def remaining = team.count { |pokemon| !pokemon.fainted? }

  # A locked request (recharge, Outrage, Struggle) lists a single move without pp.
  def moves
    return [] if force_switch?

    active_slot.fetch("moves", []).each_with_index.filter_map do |move, index|
      next if move["disabled"] || move["pp"]&.zero?

      Move.new(slot: index + 1, id: move.fetch("id"))
    end
  end

  # The Pokémon a switch can pick: a fainted teammate when Revival Blessing forces the switch, else the healthy bench.
  def switches
    return team.select(&:fainted?) if force_switch? && active&.reviving

    can_switch? ? bench : []
  end

  # The move or Pokémon a /choose choice like "move 2" refers to.
  def option_name(choice)
    kind, slot = choice.split
    case kind
    when "move" then active_slot.dig("moves", slot.to_i - 1, "move")
    when "switch" then team[slot.to_i - 1].species
    else choice
    end
  end

  private

  def active_slot = @data.fetch("active", []).first || {}

  def species(entry) = entry.fetch("details").split(",").first
end
