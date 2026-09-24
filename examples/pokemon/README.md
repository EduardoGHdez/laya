# Pokémon Showdown example

Laya plays [Pokémon Showdown](https://github.com/smogon/pokemon-showdown) Gen 9 Random Battles on a local server. Each turn it answers three questions in one `predict` call: whether to switch out, which move to use, and which Pokémon to bring in. You can watch it play against itself in the terminal, or challenge it yourself in the browser.

## Requirements

- Ruby 3.3+ and Bundler
- Node.js 22+ with npm, for the Showdown server (`brew install node`)
- git
- About 2 GB of disk and RAM for the Laya model, plus internet access the first time

## Setup

```bash
bin/setup
```

This fetches Showdown at a pinned commit into `vendor/pokemon-showdown`, builds it, exports its move, species and type data to `vendor/pokedex.json`, and runs `bundle install`. You can run it again safely.

The Laya model (about 1.7 GB) downloads the first time `bin/play` runs. To fetch it ahead of time:

```bash
bundle exec ../../exe/laya download
```

## Running

Start the server in one terminal and leave it running:

```bash
bin/server
```

It listens on http://localhost:8000. It runs with `--no-security` so bots can pick a name without an account, so use it only locally.

### Laya vs Laya

```bash
bin/play --battles 2
```

`LayaBot` and `LayaRival` connect, and LayaRival challenges LayaBot until 2 battles have finished. Both use the same loaded model, so they play the same way. Only LayaBot's decisions are printed, and the summary counts wins and losses from its side:

```
2 won, 0 lost, 0 tied (100% win rate), 79.5 turns on average, Laya switched out voluntarily in 2% of its decisions.
```

Laya decides for both sides, and two copies of the same model can stall each other, so a battle takes anywhere from a couple of minutes to ten. `--max-turns` forfeits one that drags on.

### You vs Laya

```bash
bin/play --human
```

Then:

1. Open http://localhost:8000. The page loads Showdown's client from play.pokemonshowdown.com, so it needs internet access.
2. Choose any name except `LayaBot` or `LayaRival`.
3. Find `LayaBot` (for example with `/challenge LayaBot` in the chat box) and challenge it to **[Gen 9] Random Battle**. Challenges in other formats are rejected, and the terminal says why.

LayaBot keeps accepting challenges until you press Ctrl-C, which prints the summary.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `--battles N` | 1 | Battles to play against LayaRival |
| `--human` | off | Wait for challenges from the browser instead |
| `--quiet` | off | Print only each battle's result and the summary |
| `--max-turns N` | 300 | Forfeit a battle that goes past N turns |
| `--server URL` | `ws://localhost:8000/showdown/websocket` | Showdown WebSocket URL |

## Reading the output

Every Laya decision prints a block like this:

```
Turn 5  Raikou 100%  vs  Porygon2 40%
  switch out?  0.00
  moves   thunderbolt 0.45 · scald 0.23 · calmmind 0.17 · shadowball 0.15
  switch  grafaiai 0.30 · arceusrock 0.28 · blastoise 0.22 · misdreavus 0.20
  → Thunderbolt
```

- **First line:** the turn, then our active Pokémon and the opponent's, with HP and status.
- **`switch out?`:** Laya's probability that it should switch rather than attack. Above 0.5, it switches.
- **`moves` and `switch`:** Laya's probability for each option, highest first. Each option was described to Laya with facts from Showdown's data, such as `Ground, physical, 100 power, super effective (2x)` or `Water/Flying, 80% HP, takes 0.5x from its types, hits it 2x`.
- **`→`:** what was played.

A line is left out when that question wasn't asked. For example, only `switch` appears after a faint, and only `moves` appears when the Pokémon is trapped. Lines starting with `!` mean a choice was rejected or Laya failed. In that case the bot falls back to a legal choice and the battle goes on.

## How it works

| File | Role |
| --- | --- |
| `bin/play` | CLI: connects the bots, runs the battles, prints the summary |
| `lib/showdown_client.rb` | WebSocket connection, login and Showdown commands, the only networked code |
| `lib/player.rb` | Accepts challenges and answers each battle's requests with a trainer |
| `lib/battle_room.rb` | One battle in progress: its state, the pending request, and whether the turn's log has arrived |
| `lib/battle.rb` | Battle state from the protocol log: active Pokémon, HP, status, faints, winner |
| `lib/request.rb` | A parsed request: usable moves and the Pokémon that can switch in |
| `lib/challenge.rb` | Parses a challenge from a private message |
| `lib/trainer.rb` | Asks Laya which option to pick, in one `laya.predict` call |
| `lib/matchup.rb` | Describes the battle and each option to Laya with facts from the pokedex |
| `lib/random_trainer.rb` | Picks a random legal option when Laya fails |
| `lib/decision.rb` | What a trainer chose, with the probabilities shown in the output |
| `lib/transcript.rb` | Prints each decision and rejected challenge |
| `lib/scoreboard.rb` | Tallies results and prints the summary |
| `lib/pokedex.rb` | Move, species and type-effectiveness lookups in `vendor/pokedex.json` |

## Tests

```bash
bundle exec rspec
```

The specs use fixtures and a stubbed Laya, so they need neither the server nor the model.

## Troubleshooting

- **`Run bin/setup first.`:** `vendor/pokedex.json` is missing, or setup didn't finish.
- **`Can't reach ws://localhost:8000/...`:** start `bin/server` first.
- **`Node.js 22 or later is required`:** the pinned Showdown doesn't run on older Node versions.
- **Stuck on `Loading Laya...`:** the model is loading, or downloading on the first run.
- **`Laya couldn't load: ...`:** the model download or load failed. Try `bundle exec ../../exe/laya download` to see the error.
- **Two runs at once:** both use the names `LayaBot` and `LayaRival`, so run one `bin/play` at a time.
