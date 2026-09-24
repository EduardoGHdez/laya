# What a trainer chose for one request. `choice` follows /choose: "move 2", "switch 3" or "default".
# The probabilities are only for display, and are nil when that question wasn't asked.
Decision = Data.define(:choice, :switch_out, :moves, :switches) do
  # Lets the server's autoChoose pick, which is always legal.
  def self.default = new(choice: "default")

  def initialize(choice:, switch_out: nil, moves: nil, switches: nil) = super

  def switch? = choice.start_with?("switch")

  # A switch chosen over attacking, rather than one forced by a faint.
  def voluntary_switch? = switch? && !switch_out.nil?
end
