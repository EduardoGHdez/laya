# Laya

[![CI](https://github.com/EduardoGHdez/laya/actions/workflows/ci.yml/badge.svg)](https://github.com/EduardoGHdez/laya/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/laya)](https://rubygems.org/gems/laya)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.3-CC342D?logo=ruby)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

Run [Laya](https://laya.convaiinnovations.com/), Convai Innovations' open-source "System-1" decision model, from Ruby. It runs locally on the CPU through ONNX Runtime.

You give Laya a **state** (a ticket, an email, any JSON) and some **typed questions**. It returns every answer with calibrated probabilities in a single forward pass, in a few hundred milliseconds on a laptop CPU.

```ruby
laya = Laya.new

ticket = {
  subject: "Refund not received",
  body: "I cancelled my subscription two weeks ago and I still have not received my refund. " \
    "This is the third time I am writing. If this is not resolved I will dispute the charge with my bank."
}

result = laya.predict(ticket, {
  department: {type: :choice, instructions: "Which team should handle this ticket?",
               criteria: {billing: "payments, refunds, invoices", support: "product help and bugs", sales: "new purchases"}},
  churn_risk: {type: :noul, instructions: "Is the customer likely to cancel or dispute?"}
})

result[:department].choice  # => "billing"
result[:churn_risk].noul    # => 0.0988
```

## Installation

```ruby
# Gemfile
gem "laya"
```

This requires Ruby 3.3+. The runtime dependencies are [`onnxruntime`](https://github.com/ankane/onnxruntime-ruby) and [`tokenizers`](https://github.com/ankane/tokenizers-ruby), which ship prebuilt binaries.

The model itself is about 1.7 GB, published at [receptron/laya-onnx](https://huggingface.co/receptron/laya-onnx). It downloads on first use into `~/.cache/receptron-laya`, so a machine running both downloads it only once. You can also fetch it ahead of time; see [Downloading the model](#downloading-the-model). Budget about 2 GB of RAM once it's loaded.

## Asking questions

`predict(state, questions)` answers every question about one state in a single forward pass.

- **`state`** is a String, or anything JSON-serializable (Hash, Array, numbers). Long states are truncated to the model's 512-token window.
- **`questions`** is a Hash of `name => question`. Names and `type` can be Symbols or Strings, and the answers come back under the same keys.

### The three question types

The `choice` and `score` examples below use `laya` and `ticket` from the top of this README.

| Type | Use it for | `criteria` | Answer |
| --- | --- | --- | --- |
| `choice` | Picking one option | `{label => description}`, or `[label, ...]` | `choice`, `probabilities`, `confidence` |
| `score` | A level on an ordered scale | `[lowest, ..., highest]` | `score`, `probabilities`, `legend`, `confidence` |
| `noul` | A yes/no probability | optional `{true => "...", false => "..."}` | `noul` |

**choice** picks the most likely label and gives the probability of each one:

```ruby
result = laya.predict(ticket, {
  department: {
    type: :choice,
    instructions: "Which team should handle this ticket?",
    criteria: {billing: "payments, refunds, invoices", support: "product help and bugs", sales: "new purchases"}
  }
})

result[:department].choice        # => "billing"
result[:department].probabilities # => {"billing" => 0.9415, "support" => 0.031, "sales" => 0.0275}
result[:department].confidence    # => 0.7603 (1 = certain, 0 = evenly spread)
```

**score** returns the expected level, from 0 up to the number of levels minus 1, plus the distribution:

```ruby
result = laya.predict(ticket, {
  urgency: {
    type: :score,
    instructions: "How urgent is this ticket?",
    criteria: ["not urgent", "somewhat urgent", "urgent", "critical"]
  }
})

result[:urgency].score         # => 1.3886 (between "somewhat urgent" and "urgent")
result[:urgency].probabilities # => {"0" => 0.1752, "1" => 0.2947, "2" => 0.4962, "3" => 0.0338}
result[:urgency].legend        # => {"0" => "not urgent", "1" => "somewhat urgent", ...}
```

**noul** returns P(true). The criteria are optional and let you say what true and false mean:

```ruby
result = laya.predict("Hi, my order #4521 arrived damaged, can I get a replacement?", {
  spam: {
    type: :noul,
    instructions: "Is this message spam?",
    criteria: {true => "unsolicited advertising", false => "a genuine request"}
  }
})

result[:spam].noul # => 0.1134
```

Every answer also has `type` and `act_probability`. `result.usage.input_tokens` reports how many tokens were read, and `result.to_h` returns a plain Hash.

### Tips from Laya's docs

- Keep `choice` under about 20 options. With many labels, each one gets only a few tokens and accuracy drops.
- `score` is the weakest of the three types, so it works best with coarse scales (3 to 5 levels).
- The probabilities are calibrated, so thresholds mean something. A common pattern is to act automatically above 0.85 confidence and escalate to a human below it.

See: https://huggingface.co/convaiinnovations/laya#where-jev-leads

## Configuration

```ruby
# config/initializers/laya.rb
Laya.configure do |config|
  config.cache_dir = "/var/cache/laya"
  config.session_options = {intra_op_num_threads: 4}
end
```

| Setting | Default | |
| --- | --- | --- |
| `cache_dir` | `$LAYA_CACHE`, `$XDG_CACHE_HOME/receptron-laya` or `~/.cache/receptron-laya` | Where downloads go |
| `model_dir` | `nil` | Use local model files; nothing is downloaded |
| `token` | `$HF_TOKEN` | For private or gated Hugging Face repos |
| `repo` | `"receptron/laya-onnx"` | Hugging Face repo |
| `revision` | `"main"` | Branch, tag or commit to download |
| `subfolder` | `nil` | Subfolder inside the repo |
| `providers` | `["CPUExecutionProvider"]` | ONNX Runtime execution providers |
| `session_options` | `{}` | Passed to `OnnxRuntime::InferenceSession` |
| `on_progress` | `nil` | `->(file:, received:, total:) { ... }`, called during downloads |
| `logger` | `nil` | Logs each downloaded file |

`Laya.new(**overrides)` builds a client from the global configuration plus any overrides, for example `Laya.new(model_dir: "./onnx")`.

### Loading and threads

`Laya.new` is cheap: the model loads on the first `predict` call. To load it up front, call `load!`:

```ruby
LAYA = Laya.new.load!
```

With Puma or Unicorn and `preload_app!`, load before forking so all workers share the model's memory. Clients are thread-safe, and one client per process is enough. `laya.loaded?` tells you whether the model is in memory, and `laya.close` releases it.

## Downloading the model

To avoid downloading 1.7 GB on the first request, fetch the model at build time.

**Rails:** the tasks are registered automatically and run after your initializers:

```bash
bin/rails laya:download   # fetch the model into the cache
bin/rails laya:path       # print the model directory; fails if files are missing
```

**Other Rake projects:** add `require "laya/tasks"` to your `Rakefile`, then run `rake laya:download`.

**Command line:**

```console
$ bundle exec laya download
Downloading receptron/laya-onnx@main into /Users/you/.cache/receptron-laya/receptron--laya-onnx/main
  laya.onnx.data                    42%  708.1 MB / 1607.2 MB
```

Run `bundle exec laya help` to see every command and environment variable, with its current value. The command prints the model directory on stdout, so `MODEL_DIR=$(laya path)` works in scripts.

**From Ruby:** `Laya.download` returns the directory.

**Docker:**

```dockerfile
ENV LAYA_CACHE=/models
RUN SECRET_KEY_BASE_DUMMY=1 bin/rails laya:download
```

The model then gets its own image layer, which stays cached until you change the revision.

These environment variables override the configuration in all of the above: `LAYA_CACHE`, `HF_TOKEN`, `LAYA_REPO`, `LAYA_REVISION`, `LAYA_SUBFOLDER`.

A download only fetches files that are missing or have changed size. Each file is written to a temporary file first, so an interrupted download never leaves a broken model behind. If the network is unavailable, a complete cache is used as-is.

## Errors

Every error inherits from `Laya::Error`:

| Error | When |
| --- | --- |
| `Laya::InvalidQuestionError` | A question is malformed; the message names the question |
| `Laya::InputTooLongError` | A question's options don't fit in the model's window |
| `Laya::DownloadError` | Network or Hugging Face errors (401/403 hint at `HF_TOKEN`) |
| `Laya::ModelError` | The model files are corrupt or incompatible |
| `Laya::ConfigurationError` | An invalid setting, or `model_dir` is missing files |

## Development

```bash
bundle install
bundle exec rake    # specs + StandardRB; no model needed
```

The specs that need the real model are tagged `:model` and only run when `LAYA_MODEL_DIR` is set:

```bash
bundle exec exe/laya download
LAYA_MODEL_DIR=$(bundle exec exe/laya path) bundle exec rspec
```

## License

The gem is MIT-licensed. The model weights are Apache 2.0, by [Convai Innovations](https://huggingface.co/convaiinnovations/laya). The ONNX export is by [receptron/laya](https://github.com/receptron/laya) (MIT).
