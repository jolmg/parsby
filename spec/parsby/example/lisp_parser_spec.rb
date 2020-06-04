RSpec.describe Parsby::Example::LispParser do
  include Parsby::Example::LispParser

  describe "#sexp_sequence" do
    it "parses multiple expressions with whitespace before, after and in-between" do
      expect(sexp_sequence.parse(<<~EOF))

        ;; Pair
        (foo . bar)

        (foo bar)

        -123.456

        "foo bar"

      EOF
        .to eq [
          [:foo, :bar],
          [:foo, [:bar, nil]],
          -123.456,
          "foo bar",
        ]
    end
  end

  describe "#inner_list" do
    it "accepts lists with pair ends"
  end

  describe "#hex_digit" do
    it "accepts both upper-case or lower-case"
  end

  describe "#sexp" do
    it "accepts atoms, lists, or abbreviations"
  end

  describe "#abbrev" do
    it "supports quote"
    it "supports quasiquote"
    it "supports unquote"
    it "supports unquote-splice"
  end

  describe "#escape_sequence" do
    it "allows common c-style escapes"
  end

  describe "#atom" do
    it "allows strings, numbers, or symbols"
    it "doesn't allow lists or abbreviations"
  end

  describe "#lisp_string" do
    it "allows escape sequences"
  end

  describe "#list" do
    it "accepts lists with parenthesis" do
      expect(list.parse "(foo)").to eq [:foo, nil]
    end

    it "accepts lists with brackets" do
      expect(list.parse "[foo]").to eq [:foo, nil]
    end
 
    it "doesn't accept lists that mix parentheses and brackets" do
      expect { list.parse "(foo]" }.to raise_error Parsby::ExpectationFailed
      expect { list.parse "[foo)" }.to raise_error Parsby::ExpectationFailed
    end

    it "interprets the empty list as nil ('cause they're equivalent in lisp)" do
      expect(list.parse "()").to eq nil
    end

    it "accepts nesting" do
      expect(list.parse "([()])").to eq [[nil, nil], nil]
    end
  end

  describe "#number" do
    it "returns floats" do
      expect(number.parse "0").to be_a Float
    end

    it "accepts signs" do
      expect(number.parse "-5").to eq -5
      expect(number.parse "+5").to eq 5
    end

    it "accepts fractional part" do
      expect(number.parse "123.456").to eq 123.456
    end
  end

  describe "#symbol" do
    it "accepts word characters" do
      expect(symbol.parse "Foo_bar_2").to eq :Foo_bar_2
    end

    it "accepts some character symbols" do
      expect(symbol.parse "!$%&*+-/:<=>?@^_~").to eq :"!$%&*+-/:<=>?@^_~"
    end

    it "doesn't accept character symbols (potentially) used for syntax" do
      expect { symbol.parse ")" }.to raise_error Parsby::ExpectationFailed
      expect { symbol.parse "(" }.to raise_error Parsby::ExpectationFailed
      expect { symbol.parse "." }.to raise_error Parsby::ExpectationFailed
      expect { symbol.parse "'" }.to raise_error Parsby::ExpectationFailed
      expect { symbol.parse "," }.to raise_error Parsby::ExpectationFailed
      expect { symbol.parse "`" }.to raise_error Parsby::ExpectationFailed
      expect { symbol.parse '"' }.to raise_error Parsby::ExpectationFailed
      expect { symbol.parse "[" }.to raise_error Parsby::ExpectationFailed
      expect { symbol.parse "]" }.to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#whitespace_1" do
    it "includes comments" do
      expect(whitespace_1.parse "  ;; comment\n  foo")
        .to eq "  ;; comment\n  "
    end
  end
end
