RSpec.describe Laya::Questions do
  def normalize(question_definition) = Laya::Questions.normalize(:q, question_definition)

  describe ".normalize" do
    it "keeps choice Hash criteria in order, with nil for missing descriptions" do
      question = normalize({
        type: :choice,
        instructions: "Pick",
        criteria: {a: "first", b: nil}
      })

      expect(question.type).to eq "choice"
      expect(question.type_id).to eq 0
      expect(question.criteria).to eq({"a" => "first", "b" => nil})
    end

    it "turns a choice Array into labels without descriptions" do
      question = normalize({
        "type" => "choice",
        "instructions" => "Pick",
        "criteria" => %w[x y]
      })

      expect(question.criteria).to eq({"x" => nil, "y" => nil})
    end

    it "keeps score levels as strings" do
      question = normalize({
        type: "score",
        instructions: "How much?",
        criteria: ["low", :high]
      })

      expect([question.type_id, question.criteria]).to eq [1, %w[low high]]
    end

    it "defaults noul criteria to an empty Hash and stringifies keys" do
      question = normalize({type: :noul, instructions: "Is it?"})

      expect(question.criteria).to eq({})
    end

    it "stringifies keys noul criteria" do
      question = normalize({type: :noul, instructions: "Is it?", criteria: {true => "yes"}})

      expect(question.criteria).to eq({"true" => "yes"})
    end

    it "serializes Hash instructions as JSON" do
      question = normalize({type: :noul, instructions: {goal: "détecter", n: 1}})

      expect(question.instructions).to eq '{"goal":"détecter","n":1}'
    end
  end

  describe "#options" do
    it "renders choice like rl_common.render_options" do
      question = normalize({type: :choice, instructions: "i", criteria: {a: "first", b: nil, c: ""}})
      other_question = normalize({type: :choice, instructions: "i", criteria: %w[x y]})

      expect(question.options).to eq ["a: first", "b", "c"]
      expect(other_question.options).to eq %w[x y]
    end

    it "renders score like rl_common.render_options" do
      question = normalize({type: :score, instructions: "i", criteria: %w[low high]})

      expect(question.options).to eq ["level 0: low", "level 1: high"]
    end

    it "renders default noul like rl_common.render_options" do
      question = normalize({type: :noul, instructions: "i"})

      expect(question.options).to eq [
        "false: no, the statement does not hold",
        "true: yes, the statement holds"
      ]
    end

    it "reders noul like rl_common.render_options" do
      question = normalize({
        type: :noul,
        instructions: "i",
        criteria: {"true" => "spam", "false" => ""}
      })

      expect(question.options).to eq ["false: no, the statement does not hold", "true: spam"]
    end
  end

  describe ".normalize_all" do
    it "keeps the caller's keys" do
      all = Laya::Questions.normalize_all({
        :a => {type: :noul, instructions: "x"},
        "b" => {type: :noul, instructions: "y"}
      })

      expect(all.keys).to eq [:a, "b"]
    end

    it "requires a non-empty Hash" do
      expect { Laya::Questions.normalize_all({}) }.to raise_error(Laya::InvalidQuestionError, /at least one question/)
      expect { Laya::Questions.normalize_all([]) }.to raise_error(Laya::InvalidQuestionError, /must be a Hash/)
    end
  end

  describe "validation" do
    it "rejects a question that is not a Hash" do
      expect { normalize("nope") }
        .to raise_error(Laya::InvalidQuestionError, "question :q: must be a Hash")
    end

    it "rejects an unknown type" do
      expect { normalize({type: :rank, instructions: "i"}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: type must be one of choice, score, noul (got :rank)")
    end

    it "rejects missing instructions" do
      expect { normalize({type: :noul}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: instructions must be a String or Hash")
    end

    it "rejects blank instructions" do
      expect { normalize({type: :noul, instructions: "  "}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: instructions can't be blank")
    end

    it "rejects a choice without criteria" do
      expect { normalize({type: :choice, instructions: "i"}) }
        .to raise_error(
          Laya::InvalidQuestionError,
          "question :q: choice criteria must be a Hash of label => description or an Array of labels"
        )
    end

    it "rejects a choice with a single option" do
      expect { normalize({type: :choice, instructions: "i", criteria: ["only"]}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: choice needs at least 2 options")
    end

    it "rejects a choice with duplicate labels" do
      expect { normalize({type: :choice, instructions: "i", criteria: {:a => nil, "a" => nil}}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: choice labels must be unique")
    end

    it "rejects score criteria that are not an Array" do
      expect { normalize({type: :score, instructions: "i", criteria: {a: 1}}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: score criteria must be an Array of levels, lowest first")
    end

    it "rejects a score with a single level" do
      expect { normalize({type: :score, instructions: "i", criteria: ["one"]}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: score needs at least 2 levels")
    end

    it "rejects noul criteria with keys other than true and false" do
      expect { normalize({type: :noul, instructions: "i", criteria: {maybe: "x"}}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: noul criteria must be a Hash with only true and false keys")
    end

    it "rejects noul criteria that are not a Hash" do
      expect { normalize({type: :noul, instructions: "i", criteria: "x"}) }
        .to raise_error(Laya::InvalidQuestionError, "question :q: noul criteria must be a Hash with only true and false keys")
    end
  end
end
