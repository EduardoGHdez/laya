# A challenge received as a private message, like "|pm| LayaRival| LayaBot|/challenge gen9randombattle|...".
Challenge = Data.define(:user, :format) do
  # Returns nil for any other line, including a cancelled challenge ("/challenge" with no format).
  def self.parse(line)
    _, type, from, _to, message = line.split("|", 5)
    return unless type == "pm" && message&.start_with?("/challenge ")

    # `from` carries a rank prefix (" ", "+") and "@!" when the user is away.
    new(user: from[1..].delete_suffix("@!"), format: message.delete_prefix("/challenge ").split("|").first)
  end
end
