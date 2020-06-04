RSpec.describe Parsby::Combinators do
  include Parsby::Combinators

  describe "#many" do
    it "applies parser repeatedly and returns a list of the results" do
      expect(many(string("foo")).parse "foofoofoo")
        .to eq ["foo", "foo", "foo"]
    end

    it "returns empty list when parser couldn't be applied" do
      expect(many(string("bar")).parse "foofoofoo")
        .to eq []
    end
  end

  describe "#many_1" do
    it "fails when parser couldn't be applied even once" do
      expect { many_1(string("bar")).parse "foofoofoo" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#any_char" do
    it "raises exception on EOF" do
      expect { any_char.parse "" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#decimal" do
    it "parses decimal numbers" do
      expect(decimal.parse("123")).to eq 123
    end

    it "does not accept anything other than sign-less positive decimal integers" do
      expect(decimal.parse("123.45")).to eq 123
      expect { decimal.parse("-123") }
        .to raise_error Parsby::ExpectationFailed
      expect { decimal.parse("+123") }
        .to raise_error Parsby::ExpectationFailed
    end

    it "expects at least one decimal digit" do
      expect { decimal.parse("foo") }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#string" do
    it "parses the string provided" do
      expect(string("foo").parse("foo")).to eq "foo"
    end
    
    # XXX: Backtracking should be handled BackedIO, but I've implemented
    # backtracking explicitely for #string (done before BackedIO). Because
    # of that, I thought this test would fail for restoring twice, but it
    # doesn't... It doesn't make a difference if #string restores on its
    # own or not, and I'd like to know why.
    it "backtracks properly on failure" do
      s = StringIO.new "barbaz"
      expect { string("foo").parse(s) }.to raise_error Parsby::ExpectationFailed
      expect(s.read).to eq "barbaz"

      s = StringIO.new "baz"
      expect { string("foobar").parse(s) }.to raise_error Parsby::ExpectationFailed
      expect(s.read).to eq "baz"
    end
  end

  describe "#char_matching" do
    it "matches a single char with whatever =~ supports (regexes)" do
      expect(char_matching(/\A\d\z/).parse("123")).to eq "1"
    end
  end

  describe "#whitespace_1" do
    it "like whitespace, but raises error when it doesn't match even once" do
      expect(whitespace_1.parse " \tfoo").to eq " \t"
      expect { whitespace_1.parse "foo" }.to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#whitespace" do
    it "parses continuous whitespace (' ', '\\t', '\\r', '\\n')" do
      expect(whitespace.parse " \r\n\tfoo").to eq " \r\n\t"
      expect(whitespace.parse "foo").to eq ""
    end
  end

  describe "#lazy" do
    it "delays parser construction until parsing time" do
      expect(lazy { raise }).to be_a Parsby
      expect { lazy { raise }.parse("foo") }.to raise_error RuntimeError
    end

    it "allows for recursive parser expressions avoiding stack-overflow" do
      expect(
        Module.new do
          extend Parsby::Combinators

          def self.parenthesis
            empty \
              << string("(") \
              << optional(lazy { parenthesis }) \
              << string(")")
          end
        end.parenthesis.parse("(())")
      ).to eq ["(", ["(", nil, ")"], ")"]
    end
  end

  describe "#peek" do
    it "makes a parser not consume input" do
      expect(StringIO.new("foobar").tap {|io| peek(string("foo")).parse(io) }.read(6))
        .to eq "foobar"
    end
  end

  describe "#join" do
    it "joins the resulting array of the provided parser" do
      expect(join(many(string("foo") < string(";"))).parse("foo;foo;"))
        .to eq "foofoo"
    end
  end

  describe "#sep_by_1" do
    it "is like sep_by, but fails if it can't match even once" do
      expect(sep_by_1(string("foo"), string(", ")).parse "foo, foo, foo")
        .to eq ["foo", "foo", "foo"]
      expect(sep_by_1(string("foo"), string(", ")).parse "foo")
        .to eq ["foo"]
      expect { sep_by_1(string("foo"), string(", ")).parse "bar, bar, bar" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#sep_by" do
    it "is like many, but allowing you to specify a separating parser" do
      expect(sep_by(string("foo"), string(", ")).parse "foo, foo, foo")
        .to eq ["foo", "foo", "foo"]
      expect(sep_by(string("foo"), string(", ")).parse "foo")
        .to eq ["foo"]
      expect(sep_by(string("foo"), string(", ")).parse "bar, bar, bar")
        .to eq []
    end
  end

  describe "#collect" do
    it "is meant to start collecting for & for when first parser returns array" do
      expect((empty << string("foo") << string("bar")).parse "foobar").to eq ["foo", "bar"]
      expect((empty << many(string("foo")) << many(string("bar"))).parse "foofoobarbar")
        .to eq [["foo", "foo"], ["bar", "bar"]]
    end
  end

  describe "#optional" do
    it "causes parsing errors to be returned as nil results" do
      expect(optional(string("foo")).parse("foo")).to eq "foo"
      expect(optional(string("foo")).parse("bar")).to eq nil
    end
  end

  describe "#pure" do
    it "results in provided value without consuming input" do
      expect(pure("foo").parse "bar").to eq "foo"
    end

    it "doesn't consume input" do
      s = StringIO.new "bar"
      expect { pure("foo").parse s rescue nil }.not_to change { s.pos }
    end
  end

  describe "#fail" do
    it "returns parser that always fails" do
      expect { fail.parse "foo" }.to raise_error Parsby::ExpectationFailed
    end

    it "doesn't consume input" do
      s = StringIO.new "foo"
      expect { fail.parse s rescue nil }.not_to change { s.pos }
    end
  end

  describe "#choice" do
    it "tries each parser until one succeeds" do
      expect(choice(string("foo"), string("bar")).parse "bar").to eq "bar"
    end

    it "accepts multiple arguments or array arguments" do
      expect(choice(string("foo"), string("bar")).parse "bar").to eq "bar"
      expect(choice([string("foo"), string("bar")]).parse "bar").to eq "bar"
      expect(choice([string("foo")], [string("bar")]).parse "bar").to eq "bar"
    end

    it "always fails parsing when given empty list" do
      expect { choice([]).parse "bar" }.to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#between" do
    it "(open, close, p) parses open, then p, then close, and returns the result of p" do
      expect(between(string("{{"), string("}}"), string("foo")).parse "{{foo}}").to eq "foo"
    end
  end

  describe "#eof" do
    it "succeeds only on EOF" do
      expect(eof.parse("")).to eq nil
      expect { eof.parse("x") }.to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#take_until" do
    it "returns everything until the provided parser matches" do
      expect(take_until(string("baz")).parse("foobarbaztaz")).to eq "foobar"
    end

    it "doesn't consume the input that matches the provided parser" do
      expect(
        begin
          s = StringIO.new("foobarbaztaz")
          take_until(string("baz")).parse(s)
          s.read
        end
      ).to eq "baztaz"
    end
  end

  describe "#token" do
    it "builds a token with the given name" do
      expect(token "foo").to be_a(Parsby::Token).and satisfy {|t| t.name == "foo"}
    end
  end
end
