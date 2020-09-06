RSpec.describe Parsby::Combinators do
  include Parsby::Combinators

  describe Parsby::Combinators::ModuleMethods do
    include Parsby::Combinators::ModuleMethods

    describe "#define_combinator" do
      let :mod do
        Module.new.module_exec do
          include Parsby::Combinators
          extend self
        end
      end

      it "adds automatic labeling that resembles corresponding ruby expressions of combinators" do
        expect(
          begin
            mod.define_combinator :foo do
              lit("foo")
            end
            mod.foo.label
          end
        ).to eq "foo"
      end

      it "validates arity of arguments" do
        expect {
          begin
            mod.define_combinator :foo do |x|
              lit("foo")
            end
            mod.foo.label
          end
        }.to raise_error(ArgumentError, /wrong number of arguments/)
      end

      it "shows the labels of parser arguments and inspected versions of other arguments" do
        expect(
          begin
            mod.define_combinator :foo do |c, x, y|
              lit("foo")
            end
            mod.foo(3, lit("bar"), lit("baz")).label
          end
        ).to eq 'foo(3, lit("bar"), lit("baz"))'
      end

      it "shows the labels of parser arguments when nested in Array or Hash arguments" do
        expect(
          begin
            mod.define_combinator :foo do |x, baz:|
              lit("foo")
            end
            mod.foo([3, "foobar", lit("bar")], baz: lit("baz")).label
          end
        ).to eq 'foo([3, "foobar", lit("bar")], {:baz=>lit("baz")})'
      end

      it "works with super()" do
        expect(
          begin
            mod.define_combinator :foobarbaz do
              lit("foo")
            end
            mod2 = Module.new
            mod2.include mod
            mod2.module_exec { extend self }
            mod2.define_combinator :foobarbaz do
              super() + lit("bar")
            end
            mod3 = Module.new
            mod3.include mod2
            mod3.module_exec { extend self }
            mod3.define_combinator :foobarbaz do
              super() + lit("baz")
            end
            mod3.foobarbaz.parse "foobarbaz"
          end
        ).to eq "foobarbaz"
      end
    end

    describe "#inspectable_as" do
      it "returns an object that inspects as the given lit argument" do
        expect(send(:inspectable_as, "foo").inspect).to eq "foo"
      end
    end

    describe "#inspectable_labels" do
      it "changes parsby objects to objects returning their label on inspect" do
        expect(lit("foo").inspect).to match /\A#<Parsby:/
        expect(send(:inspectable_labels, lit("foo")).inspect).to eq 'lit("foo")'
      end

      it "deeply traverses arrays and hashes, leaving non-parsby objects alone" do
        expect(
          send(
            :inspectable_labels,
            [3, { foo: lit("foo") }]
          ).inspect
        ).to eq '[3, {:foo=>lit("foo")}]'
      end
    end
  end

  describe "#many" do
    it "applies parser repeatedly and returns a list of the results" do
      expect(many(lit("foo")).parse "foofoofoo")
        .to eq ["foo", "foo", "foo"]
    end

    it "returns empty list when parser couldn't be applied" do
      expect(many(lit("bar")).parse "foofoofoo")
        .to eq []
    end
  end

  describe "#many_1" do
    it "fails when parser couldn't be applied even once" do
      expect { many_1(lit("bar")).parse "foofoofoo" }
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

  describe "#decimal_digit" do
    it "parses single decimal digit as a lit" do
      expect(decimal_digit.parse "9").to eq "9"
    end
  end

  describe "#hex_digit" do
    it "parses single hex digit as a lit" do
      expect(hex_digit.parse "5").to eq "5"
      expect(hex_digit(:insensitive).parse "5").to eq "5"
      expect(hex_digit(:upper).parse "5").to eq "5"
      expect(hex_digit(:lower).parse "5").to eq "5"
      expect(hex_digit.parse "F").to eq "F"
      expect(hex_digit.parse "f").to eq "f"
      expect(hex_digit(:insensitive).parse "F").to eq "F"
      expect(hex_digit(:insensitive).parse "f").to eq "f"
      expect { hex_digit(:upper).parse "f" }.to raise_error Parsby::ExpectationFailed
      expect { hex_digit(:lower).parse "F" }.to raise_error Parsby::ExpectationFailed
      expect { hex_digit(:foo).parse "F" }.to raise_error ArgumentError
    end
  end

  describe "#string" do
    it "parses the lit provided" do
      expect(lit("foo").parse("foo")).to eq "foo"
    end
    
    # XXX: Backtracking should be handled BackedIO, but I've implemented
    # backtracking explicitely for #string (done before BackedIO). Because
    # of that, I thought this test would fail for restoring twice, but it
    # doesn't... It doesn't make a difference if #string restores on its
    # own or not, and I'd like to know why.
    it "backtracks properly on failure" do
      s = StringIO.new "barbaz"
      expect { lit("foo").parse(s) }.to raise_error Parsby::ExpectationFailed
      expect(s.read).to eq "barbaz"

      s = StringIO.new "baz"
      expect { lit("foobar").parse(s) }.to raise_error Parsby::ExpectationFailed
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

  describe "#spaced" do
    it "parses optional surrounding whitespace" do
      expect(spaced(lit("foo")).parse "foo").to eq "foo"
      expect(group(spaced(lit("foo")), lit("bar")).parse " foo bar").to eq ["foo", "bar"]
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
              << lit("(") \
              << optional(lazy { parenthesis }) \
              << lit(")")
          end
        end.parenthesis.parse("(())")
      ).to eq ["(", ["(", nil, ")"], ")"]
    end
  end

  describe "#peek" do
    it "makes a parser not consume input" do
      expect(StringIO.new("foobar").tap {|io| peek(lit("foo")).parse(io) }.read(6))
        .to eq "foobar"
    end
  end

  describe "#join" do
    it "joins the resulting array of the provided parser" do
      expect(join(many(lit("foo") < lit(";"))).parse("foo;foo;"))
        .to eq "foofoo"
    end
  end

  describe "#sep_by_1" do
    it "is like sep_by, but fails if it can't match even once" do
      expect(sep_by_1(lit(", "), lit("foo")).parse "foo, foo, foo")
        .to eq ["foo", "foo", "foo"]
      expect(sep_by_1(lit(", "), lit("foo")).parse "foo")
        .to eq ["foo"]
      expect { sep_by_1(lit(", "), lit("foo")).parse "bar, bar, bar" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#sep_by" do
    it "is like many, but allowing you to specify a separating parser" do
      expect(sep_by(lit(", "), lit("foo")).parse "foo, foo, foo")
        .to eq ["foo", "foo", "foo"]
      expect(sep_by(lit(", "), lit("foo")).parse "foo")
        .to eq ["foo"]
      expect(sep_by(lit(", "), lit("foo")).parse "bar, bar, bar")
        .to eq []
    end
  end

  describe "#collect" do
    it "is meant to start collecting for & for when first parser returns array" do
      expect((empty << lit("foo") << lit("bar")).parse "foobar").to eq ["foo", "bar"]
      expect((empty << many(lit("foo")) << many(lit("bar"))).parse "foofoobarbar")
        .to eq [["foo", "foo"], ["bar", "bar"]]
    end
  end

  describe "#optional" do
    it "causes parsing errors to be returned as nil results" do
      expect(optional(lit("foo")).parse("foo")).to eq "foo"
      expect(optional(lit("foo")).parse("bar")).to eq nil
    end
  end

  describe "#empty" do
    it "results in an empty list" do
      expect(empty.parse "foo").to eq []
    end

    it "doesn't consume input" do
      expect(
        begin
          s = StringIO.new "foo"
          r = empty.parse s
          [s.read, r]
        end
      ).to eq ["foo", []]
    end
  end

  describe "#single" do
    it "wraps result of provided parser into an array" do
      expect(single(lit("foo")).parse "foo").to eq ["foo"]
    end
  end

  describe "#group" do
    it "groups results of array into a list" do
      expect(group(many(lit("foo")), lit("bar")).parse "foofoobar")
        .to eq [["foo", "foo"], "bar"]
    end
  end

  describe "#parsby" do
    it "is the same as Parsby.new" do
      expect(parsby("foo") { "bar" })
        .to be_a(Parsby)
        .and satisfy {|p| p.label == "foo" }
        .and satisfy {|p| p.parse("") == "bar" }
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

  describe "#unparseable" do
    it "returns parser that always fails" do
      expect { unparseable.parse "foo" }.to raise_error Parsby::ExpectationFailed
    end

    it "doesn't consume input" do
      s = StringIO.new "foo"
      expect { unparseable.parse s rescue nil }.not_to change { s.pos }
    end
  end

  describe "#char_in" do
    it "parses one char from those in the lit argument" do
      expect(char_in("abc").parse("be")).to eq "b"
      expect(char_in("abc").parse("bc")).to eq "b"
    end
  end

  describe "#choice" do
    it "tries each parser until one succeeds" do
      expect(choice(lit("foo"), lit("bar")).parse "bar").to eq "bar"
    end

    it "accepts multiple arguments or array arguments" do
      expect(choice(lit("foo"), lit("bar")).parse "bar").to eq "bar"
      expect(choice([lit("foo"), lit("bar")]).parse "bar").to eq "bar"
      expect(choice([lit("foo")], [lit("bar")]).parse "bar").to eq "bar"
    end

    it "always fails parsing when given empty list" do
      expect { choice([]).parse "bar" }.to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#between" do
    it "(open, close, p) parses open, then p, then close, and returns the result of p" do
      expect(between(lit("{{"), lit("}}"), lit("foo")).parse "{{foo}}").to eq "foo"
    end
  end

  describe "#count" do
    it "expects parser p to parse n times" do
      expect(count(2, lit("foo")).parse("foofoofoo"))
        .to eq ["foo", "foo"]
      expect { count(2, lit("foo")).parse "foo" }
        .to raise_error Parsby::ExpectationFailed
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
      expect(take_until(lit("baz")).parse("foobarbaztaz")).to eq "foobar"
    end

    it "doesn't consume the input that matches the provided parser" do
      expect(
        begin
          s = StringIO.new("foobarbaztaz")
          take_until(lit("baz")).parse(s)
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
