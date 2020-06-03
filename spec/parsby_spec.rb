RSpec.describe Parsby do
  include Parsby::Combinators

  it "has a version number" do
    expect(Parsby::VERSION).not_to be nil
  end

  describe Parsby::ExpectationFailed do
    describe "#initialize" do
      it "takes :expected, :actual, and :at keyword arguments for use with message" do
        expect(Parsby::ExpectationFailed.new(expected: "foo", actual: "bar", at: 10).opts)
          .to eq expected: "foo", actual: "bar", at: 10
      end

      it "only at argument is required" do
        expect(Parsby::ExpectationFailed.new({}).message).to eq "at "
      end
    end

    describe "#message" do
      it "uses opts to display the user message" do
        expect(Parsby::ExpectationFailed.new(expected: "foo", actual: "bar", at: 10).message)
          .to eq "expected foo, actual \"bar\", at 10"
      end
    end

    describe "#modify!" do
      it "modifies the arguments of the exception" do
        expect(
          Parsby::ExpectationFailed
            .new(expected: "foo", actual: "bar", at: 10)
            .tap {|e| e.modify! actual: "taz" }
            .message
        ).to eq "expected foo, actual \"taz\", at 10"
      end
    end
  end

  describe Parsby::Token do
    describe "#to_s" do
      it "wraps name in angle brackets" do
        expect(Parsby::Token.new("foo").to_s).to eq "<foo>"
      end
    end

    describe "#initialize" do
      it "takes name as argument" do
        expect(Parsby::Token.new("foo").name).to eq "foo"
      end
    end

    describe "#%" do
      it "is the flipped version of Parsby's" do
        expect((Parsby::Token.new("foo") % string("foo")).label.to_s)
          .to eq "<foo>"
      end
    end
  end

  describe Parsby::BackedIO do
    let(:pipe) { IO.pipe }
    let(:r) { pipe[0] }
    let(:w) { pipe[1] }
    let(:br) { Parsby::BackedIO.new r }

    before do
      w.write "foobarbaz"
    end

    describe "#method_missing" do
      it "let's you use any underlying method of the IO" do
        expect(Parsby::BackedIO.new("foo\nbar\n").readline)
          .to eq "foo\n"
      end
    end

    describe "#read" do
      it "reads from IO and adds it to the backup" do
        expect(
          begin
            bio = Parsby::BackedIO.new("foobarbaz")
            r1 = bio.read 3
            r2 = bio.read 3
            backup = bio.instance_eval { @backup }
            [r1, r2, backup]
          end
        ).to eq ["foo", "bar", "foobar"]
      end
    end

    describe "#ungetc" do
      it "passes the character to the underlying io" do
        expect(
          Parsby::BackedIO.new("foo").tap do |bio|
            bio.read(1)
            bio.ungetc "b"
          end.instance_eval { @io }.read(3)
        ).to eq "boo"
      end

      it "slices substring of same length from the backup" do
        expect(
          Parsby::BackedIO.new("foobar").tap do |bio|
            bio.read(3)
            bio.ungetc("b")
          end.instance_eval { @backup }
        ).to eq "fo"
      end
    end

    describe "#initialize" do
      it "accepts a string as argument, turning it into a StringIO" do
        expect(Parsby::BackedIO.new("foo").instance_eval { @io })
          .to be_a StringIO
      end
    end

    describe "#restore" do
      it "restores what was read" do
        expect(br.read 1).to eq "f"
        expect(br.read 2).to eq "oo"
        br.restore
        expect(br.read 6).to eq "foobar"
      end

      it "works on nested instances" do
        expect(br.read 3).to eq "foo"

        Parsby::BackedIO.for br do |br2|
          expect(br2.read 3).to eq "bar"
          br2.restore
          expect(br2.read 3).to eq "bar"
          br2.restore
        end

        expect(br.read 6).to eq "barbaz"
        br.restore
        expect(br.read 9).to eq "foobarbaz"
      end
    end

    describe ".for" do
      it "restores on exception" do
        begin
          Parsby::BackedIO.for r do |br|
            expect(br.read 3).to eq "foo"
            raise
          end
        rescue
        end
        expect(r.read 3).to eq "foo"
      end

      it "returns the block's return value" do
        expect(Parsby::BackedIO.for(r) {|br| :x}).to eq :x
      end
    end
  end

  describe "#initialize" do
    it "accepts optional label as argument" do
      expect(Parsby.new("foo").label).to eq "foo"
    end

    it "when label is not provided, it's an unknown token" do
      expect(Parsby.new.label.class).to eq Parsby::Token
      expect(Parsby.new.label.name).to eq "unknown"
    end

    it "takes block that provides a BackedIO as argument, and which result is the result of #parse" do
      expect(Parsby.new {|io| io.class}.parse "foo").to eq Parsby::BackedIO
      expect(Parsby.new {|io| io.read(2) }.parse "foo").to eq "fo"
    end
  end

  describe "#parse" do
    it "accepts strings" do
      expect(string("foo").parse("foo")).to eq "foo"
    end

    it "accepts IO objects" do
      expect(string("foo").parse IO.pipe.tap {|(_, w)| w.write "foo"; w.close }.first)
        .to eq "foo"
    end
  end

  describe "#peek" do
    it "works like parse, but without consuming the input" do
      expect(
        begin
          s = StringIO.new "123"
          r = decimal.peek s
          [r, s.read]
        end
      ).to eq [123, "123"]
    end
  end

  describe "#ignore?" do
    it "set for parsers returned by #-@" do
      expect(string("foo")).not_to satisfy(&:ignore?)
      expect(-string("foo")).to satisfy(&:ignore?)
      expect(
        begin
          p = string("foo")
          -p
          p
        end
      ).not_to satisfy(&:ignore?)
    end
  end

  describe "#label=" do
    it "assigns strings as is" do
      expect(Parsby.new.tap {|p| p.label = "foo"}.label.to_s).to eq "foo"
    end

    it "turns it into a token if it's a symbol" do
      expect(Parsby.new.tap {|p| p.label = :foo}.label.to_s).to eq "<foo>"
    end
  end

  describe "#label" do
    it "defaults to unknown token" do
      expect(Parsby.new.label.to_s).to eq "<unknown>"
    end
  end

  describe "#*" do
    it "p * n parses p n times and returns the results in an array" do
      expect((string("foo") * 2).parse "foofoo").to eq ["foo", "foo"]
    end

    it "fails if it can't parse the number of times specified" do
      expect { (string("foo") * 3).parse "foofoo" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#+" do
    it "like &, but joins the results with +" do
      expect((string("foo") + string("bar")).parse "foobar").to eq "foobar"
    end
  end

  describe "#-@" do
    it "causes & to not include the result of this parser" do
      expect((-string("foo") & string("bar")).parse "foobar").to eq ["bar"]
      expect((string("foo") & -string("bar")).parse "foobar").to eq ["foo"]
    end
  end

  describe "#&" do
    it "parses both operands and combines their results in an array" do
      expect((string("foo") & string("bar")).parse "foobar").to eq ["foo", "bar"]
      expect((many(string("foo")) & many(string("bar"))).parse "foofoobarbar")
        .to eq ["foo", "foo", ["bar", "bar"]]
    end
  end

  describe "#|" do
    it "tries second operand if first one fails" do
      expect((string("foo") | string("bar")).parse "bar").to eq "bar"
      expect { (string("foo") | string("bar")).parse "baz" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#<" do
    it "parses left operand then right operand, and returns the result of left" do
      expect((string("foo") < string("bar")).parse "foobar").to eq "foo"
    end
  end

  describe "#>" do
    it "parses left operand then right operand, and returns the result of right" do
      expect((string("foo") > string("bar")).parse "foobar").to eq "bar"
    end
  end

  describe "#%" do
    it "sets the label of the parser" do
      expect((string("foo") % "bar").label).to eq "bar"
    end
  end

  describe "#would_succeed" do
    it "peeks to tell whether or not it would succeed" do
      expect(string("foo").would_succeed("foo")).to eq true
      expect(string("foo").would_succeed("bar")).to eq false
    end
  end

  describe "#that_fails" do
    it "tries parser argument; if argument fails, it parses with receiver; if argument succeeds, then it fails" do
      expect(decimal.that_fails(string("10")).parse("34")).to eq 34
      expect { decimal.that_fails(string("10")).parse("10") }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#fmap" do
    it "permits working with the value \"inside\" the parser, like map does with array" do
      expect(decimal.fmap {|x| x + 1}.parse("3")).to eq 4
    end
  end
end
