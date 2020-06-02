RSpec.describe LispParser do
  describe "#sexp_sequence" do
    it "parses different expressions" do
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; Pair
        (foo . bar)
      EOF
        .to eq [
          [:foo, :bar],
        ]
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; A list
        (+ foo bar)
      EOF
        .to eq [
          [:+, [:foo, [:bar, nil]]],
        ]
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; Same list as pairs
        (+ . (foo . (bar . ())))
      EOF
        .to eq [
          [:+, [:foo, [:bar, nil]]],
        ]
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; List with pair end
        (foo bar . baz)
      EOF
        .to eq [
          [:foo, [:bar, :baz]],
        ]
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; Quote abbreviation
        'foo
      EOF
        .to eq [
          [:quote, [:foo, nil]]
        ]
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; Quasiquote and unquote abbreviations
        `(foo ,bar)
      EOF
        .to eq [
          [:quasiquote, [[:foo, [[:unquote, [:bar, nil]], nil]], nil]]
        ]
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; Numbers
        -123.456
      EOF
        .to eq [
          -123.456,
        ]
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; Strings
        "stri\\"ng\\n \\xfff"
      EOF
        .to eq [
          "stri\"ng\n \xFFf".force_encoding("BINARY"),
        ]
    end
  end
end
