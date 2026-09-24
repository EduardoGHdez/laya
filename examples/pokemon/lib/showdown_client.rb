require "async"
require "async/http/endpoint"
require "async/websocket/client"
require_relative "pokedex"

# A WebSocket connection to a Showdown server, logged in as one user. The only class that touches the network.
class ShowdownClient
  class Error < StandardError; end

  DEFAULT_URL = "ws://localhost:8000/showdown/websocket"

  attr_reader :name

  # Connects, logs in as `name` (the server must run with --no-security), and yields the client.
  def self.open(url, name)
    Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse(url)) do |connection|
      client = new(connection, name)
      client.login
      yield client
    end
  end

  def initialize(connection, name)
    @connection = connection
    @name = name
  end

  # Sends `text` to a room. An empty room means a global command.
  def send_message(room, text)
    @connection.send_text("#{room}|#{text}")
    @connection.flush
  end

  # "/utm null" clears any team set before, since random battles generate their own.
  def challenge(user, format)
    send_message("", "/utm null")
    send_message("", "/challenge #{user}, #{format}")
  end

  def accept(user)
    send_message("", "/utm null")
    send_message("", "/accept #{user}")
  end

  def reject(user) = send_message("", "/reject #{user}")

  def choose(room, choice, rqid) = send_message(room, "/choose #{choice}|#{rqid}")

  def forfeit(room) = send_message(room, "/forfeit")

  def leave(room) = send_message(room, "/leave")

  # Yields [room, lines] for each frame until the connection closes. Global frames have an empty room.
  def each_frame
    while (message = @connection.read)
      lines = message.to_str.split("\n")
      room = lines.first&.start_with?(">") ? lines.shift.delete_prefix(">") : ""
      yield room, lines
    end
  end

  def login
    each_frame do |_room, lines|
      lines.each do |line|
        send_message("", "/trn #{name},0,") if line.start_with?("|challstr|")
        raise Error, "Could not log in as #{name}: #{line.split("|").last}" if line.start_with?("|nametaken|")
      end
      return if lines.any? { |line| line.start_with?("|updateuser|") && Pokedex.to_id(line.split("|")[2]) == Pokedex.to_id(name) }
    end
    raise Error, "The server closed the connection before #{name} logged in"
  end
end
