RSpec.describe LispParser do
  describe "#sexp_sequence" do
    it "parses different expressions" do
      expect(LispParser.sexp_sequence.parse(<<~EOF))
        ;; A comment
        (+ foo bar)

        ;; pair
        (foo . bar)

        ;; list with pair end
        (foo bar . baz)

        ;; numbers
        -123.456

        ;; strings
        "stri\\"ng\\n \\xfff"
      EOF
        .to eq [
          [:+, [:foo, [:bar, nil]]],
          [:foo, :bar],
          [:foo, [:bar, :baz]],
          -123.456,
          "stri\"ng\n \xFFf",
        ]
    end
  end
end
