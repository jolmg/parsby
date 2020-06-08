RSpec.describe Parsby do
  include Parsby::Combinators

  it "has a version number" do
    expect(Parsby::VERSION).not_to be nil
  end

  describe Parsby::Failure do
    describe "#initialize" do
      it "takes 2 pos and a label" do
        expect(Parsby::Failure.new(10, 12, "foo"))
          .to satisfy {|e| e.starts_at == 10 }
          .and satisfy {|e| e.ends_at == 12 }
          .and satisfy {|e| e.label == "foo" }
      end
    end

    describe "#length" do
      it "returns difference between starting and ending positions" do
        expect(Parsby::Failure.new(7, 10, "foo").length)
          .to eq 3
      end
    end

    describe "#starts_at_col" do
      it "returns starts_at converted to a col for a given line starting position" do
        expect(Parsby::Failure.new(5, 10, "foo").starts_at_col(3))
          .to eq 2
      end

      it "returns negative, when it's in a previous line" do
        expect(Parsby::Failure.new(5, 10, "foo").starts_at_col(7))
          .to eq(-2)
      end
    end


    describe "#ends_at_col" do
      it "returns ends_at converted to a col for a given line starting position" do
        expect(Parsby::Failure.new(5, 10, "foo").ends_at_col(8))
          .to eq 2
      end

      it "returns negative, when it's in a previous line" do
        expect(Parsby::Failure.new(5, 10, "foo").ends_at_col(12))
          .to eq(-2)
      end
    end

    describe "#underline" do
      it "renders a visualization of where in the current line the failure was located" do
        expect(Parsby::Failure.new(5, 10, "foo").underline(0))
          .to eq "\\---/"
      end

      it "clips the range when it's out of bounds" do
        expect(Parsby::Failure.new(5, 10, "foo").underline(6))
          .to eq "---/"
      end

      it "returns empty string when range is completely out of bounds" do
        expect(Parsby::Failure.new(5, 10, "foo").underline(20))
          .to eq ""
      end

      it "uses | when length is 0" do
        expect(Parsby::Failure.new(5, 5, "foo").underline(0))
          .to eq "|"
      end

      it "uses V when length is 1" do
        expect(Parsby::Failure.new(5, 6, "foo").underline(0))
          .to eq "V"
      end
    end
  end

  describe Parsby::ExpectationFailed2 do
    describe "#initialize" do
      it "can be provided just an BackedIO, leaving the expectations list as empty" do
        expect(
          Parsby::ExpectationFailed2
            .new(Parsby::BackedIO.new("foobar"))
            .failures
        ).to eq []
      end

      it "accepts an expectation to start up the expectations list" do
        expect(
          Parsby::ExpectationFailed2
            .new(Parsby::BackedIO.new("foo"), Parsby::Failure.new(2, 4, "bar"))
            .failures
            .first
            .label
        ).to eq "bar"
      end
    end

    describe "#message" do
      it "displays the current line and the list of expectations as underlined ranges" do
        expect(
          Parsby::ExpectationFailed2
            .new(
              Parsby::BackedIO
                .new("taz\nfoo bar foo bax foo")
                .tap {|bio| bio.read(12) },
              Parsby::Failure.new(18, 19, '"b"'),
            )
            .tap do |e|
              e.failures << Parsby::Failure.new(16, 18, '"bar"')
              e.failures << Parsby::Failure.new(16, 16, '"foo" or "bar"')
              e.failures << Parsby::Failure.new(8, 16, 'sep_by_count("foo" or "bar", " ", 4)')
              e.failures << Parsby::Failure.new(0, 8, 'count(4, eol | sep_by_count("foo" or "bar", " ", 4))')
            end
            .message
        ).to eq <<~ERROR
          line 2:
            foo bar foo bax foo
                          V expected: "b"
                        \\/ expected: "bar"
                        | expected: "foo" or "bar"
                \\------/ expected: sep_by_count("foo" or "bar", " ", 4)
            ---/ expected: count(4, eol | sep_by_count("foo" or "bar", " ", 4))
        ERROR
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

    describe "#==" do
      it "compares tokens" do
        expect(Parsby::Token.new("foo")).to eq Parsby::Token.new("foo")
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

    describe "#line_number" do
      it "starts at 1" do
        expect(Parsby::BackedIO.new("foo").line_number).to eq 1
      end

      it "returns the number of the current line" do
        expect(
          Parsby::BackedIO
            .new("\nfoo\n\nbar")
            .tap {|bio| bio.read(8)}
            .line_number
        ).to eq 4
      end

      it "takes into account that it may need the additional backup inner BackedIOs" do
        expect(
          Parsby::BackedIO
            .new(
              Parsby::BackedIO
                .new("\nfoo\n\nbar")
                .tap {|bio| bio.read(8)}
            )
            .line_number
        ).to eq 4
      end
    end

    describe "#current_line_pos" do
      it "returns the position of the beginning of current line" do
        expect(
          Parsby::BackedIO
            .new("foo\nbar")
            .tap {|bio| bio.read(6) }
            .current_line_pos
        ).to eq 4
      end
    end

    describe "#grand_backup" do
      it "returns the backup of the innermost BackedIO" do
        expect(
          Parsby::BackedIO
            .new(
              Parsby::BackedIO
                .new("foobarbaz")
                .tap {|bio| bio.read(3) }
            )
            .tap {|bio| bio.read(3) }
            .grand_backup
        ).to eq "foobar"
      end
    end

    def piped(s, &b)
      r, w = IO.pipe
      w.write s
      w.close
      begin
        b.call r
      ensure
        r.close
      end
    end

    describe "#pos" do
      it "delegates to inner io" do
        io = StringIO.new "foo"
        bio = Parsby::BackedIO.new io
        expect(io).to receive(:pos)
        bio.pos
      end

      it "doesn't use grand_backup when it doesn't need to" do
        io = StringIO.new "foo"
        bio = Parsby::BackedIO.new io
        expect(bio).to_not receive(:grand_backup)
        bio.pos
      end

      it "uses grand_backup when using the io's pos fails for being a pipe" do
        piped "foo" do |io|
          bio = Parsby::BackedIO.new io
          allow(io).to receive(:pos) { raise Errno::ESPIPE }
          allow(bio).to receive(:grand_backup) { "foo" }
          expect(io).to receive(:pos)
          expect(bio).to receive(:grand_backup)
          bio.pos
        end
      end
    end

    describe "#col" do
      it "returns current position in the current line" do
        expect(
          Parsby::BackedIO
            .new("foo\nbar\nbaz")
            .tap {|bio| bio.read(10) }
            .col
        ).to eq 2
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

    describe ".peek" do
      it "is like .for, but restores the IO even if there weren't an error" do
        expect(
          begin
            io = StringIO.new "foobar"
            io.read(3)
            x = Parsby::BackedIO.peek io do |bio|
              bio.read
            end
            y = io.read
            [x, y]
          end
        ).to eq ["bar", "bar"]
      end
    end

    describe "#peek" do
      it "is like #read, but restores what it reads" do
        expect(
          begin
            io = Parsby::BackedIO.new "foobar"
            r1 = io.read 3
            p = io.peek 3
            r2 = io.read 3
            [r1, p, r2]
          end
        ).to eq ["foo", "bar", "bar"]
      end
    end

    describe "#initialize" do
      it "accepts a string as argument, turning it into a StringIO" do
        expect(Parsby::BackedIO.new("foo").instance_eval { @io })
          .to be_a StringIO
      end
    end

    describe "#back_context" do
      it "gets text from current position backward until first of newline, BOF" do
        expect(
          Parsby::BackedIO
            .new("foo\nbar")
            .tap {|io| io.read 3 }
            .back_context
        ).to eq "foo"

        expect(
          Parsby::BackedIO
            .new("foo\nbar")
            .tap {|io| io.read 4 }
            .back_context
        ).to eq ""

        expect(
          Parsby::BackedIO
            .new("foo\nbar")
            .tap {|io| io.read }
            .back_context
        ).to eq "bar"

        expect(
          Parsby::BackedIO
            .new("foobar")
            .back_context
        ).to eq ""
      end

      it "delegates to inner BackedIO if available for more backup" do
        expect(
          begin
            inner = Parsby::BackedIO.new "foobarbaz"
            inner.read(3)
            outer = Parsby::BackedIO.new inner
            outer.read(3)
            outer.back_context
          end
        ).to eq "foobar"
      end
    end

    describe "#forward_context" do
      it "gets text from current position forward until first of newline, EOF" do
        expect(
          Parsby::BackedIO
            .new("foobar\n")
            .tap {|io| io.read 3 }
            .forward_context
        ).to eq "bar"

        expect(
          Parsby::BackedIO
            .new("foobar")
            .tap {|io| io.read 3 }
            .forward_context
        ).to eq "bar"
      end
    end

    describe "#current_line" do
      it "returns current line, without consuming input" do
        expect(
          begin
            s = Parsby::BackedIO.new "foo\nbar baz\n"
            s.read(7)
            [s.current_line, s.read]
          end
        ).to eq ["bar baz", " baz\n"]

        expect(
          begin
            s = Parsby::BackedIO.new "foo\nbar baz\n"
            s.read(4)
            [s.current_line, s.read]
          end
        ).to eq ["bar baz", "bar baz\n"]

        expect(
          begin
            s = Parsby::BackedIO.new "foo\nbar baz\n"
            s.read(3)
            [s.current_line, s.read]
          end
        ).to eq ["foo", "\nbar baz\n"]
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
        .to raise_error Parsby::ExpectationFailed2
    end
  end

  describe "#<<" do
    it "appends right operand to list result of left operand" do
      expect((many(string("foo")) << string("bar")).parse "foofoobar")
        .to eq ["foo", "foo", "bar"]
    end
  end

  describe "#+" do
    it "joins the results with +" do
      expect((string("foo") + string("bar")).parse "foobar").to eq "foobar"
    end
  end

  describe "#|" do
    it "tries second operand if first one fails" do
      expect((string("foo") | string("bar")).parse "bar").to eq "bar"
      expect { (string("foo") | string("bar")).parse "baz" }
        .to raise_error Parsby::ExpectationFailed2
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

  describe "#on_catch" do
    it "runs block when catching ExpectationFailed2, allowing one to modify the exception" do
      expect(
        begin
          string("foo")
            .on_catch {|e| e.failures.first.ends_at += 100 }
            .parse "fox"
        rescue Parsby::ExpectationFailed2 => e
          e.failures.first.ends_at
        end
      ).to eq 103
    end
  end

  describe "#that_fails" do
    it "tries parser argument; if argument fails, it parses with receiver; if argument succeeds, then it fails" do
      expect(decimal.that_fails(string("10")).parse("34")).to eq 34
      expect { decimal.that_fails(string("10")).parse("10") }
        .to raise_error Parsby::ExpectationFailed2
    end
  end

  describe "#fmap" do
    it "permits working with the value \"inside\" the parser, like map does with array" do
      expect(decimal.fmap {|x| x + 1}.parse("3")).to eq 4
    end
  end
end
