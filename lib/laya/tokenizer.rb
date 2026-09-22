require "tokenizers"

module Laya
  # The checkpoint's ModernBERT tokenizer and the special ids the sequence layout needs.
  class Tokenizer
    attr_reader :special_ids

    def initialize(dir)
      @tokenizer = Tokenizers.from_file(File.join(dir, "tokenizer", "tokenizer.json"))
      @special_ids = Sequence::SpecialIds.new(
        cls: token_id("[CLS]"),
        sep: token_id("[SEP]"),
        mask: token_id("[MASK]"),
        pad: token_id("[PAD]"),
        mask_token: "[MASK]"
      )
    end

    def encode(text) = @tokenizer.encode(text, add_special_tokens: false).ids

    private

    def token_id(token) = @tokenizer.token_to_id(token) || raise(ModelError, "special token #{token} missing from tokenizer")
  end
end
