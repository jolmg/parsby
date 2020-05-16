RSpec.describe Parsby do
  it "has a version number" do
    expect(Parsby::VERSION).not_to be nil
  end

  describe :parse do
    it "accepts strings" do
      expect(Parsby.string("foo").parse "foo").to eq "foo"
    end

    it "accepts IO objects" do
      expect(Parsby.string("foo").parse IO.pipe.tap {|(_, w)| w.write "foo"; w.close }.first)
        .to eq "foo"
    end
  end

  describe :many do
    it "applies parser repeatedly and returns a list of the results" do
      expect(Parsby.many(Parsby.string("foo")).parse "foofoofoo")
        .to eq ["foo", "foo", "foo"]
    end

    it "returns empty list when parser couldn't be applied" do
      expect(Parsby.many(Parsby.string("bar")).parse "foofoofoo")
        .to eq []
    end
  end

  describe :any_char do
    it "raises exception on EOF" do
      expect { Parsby.any_char.parse "" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe :string do
    it "parses the string provided" do
      expect(Parsby.string("foo").parse("foo")).to eq "foo"
    end
    
    # XXX: Backtracking should be handled BackedIO, but I've implemented
    # backtracking explicitely for #string (done before BackedIO). Because
    # of that, I thought this test would fail for restoring twice, but it
    # doesn't... It doesn't make a difference if #string restores on its
    # own or not, and I'd like to know why.
    it "backtracks properly on failure" do
      s = StringIO.new "barbaz"
      expect { Parsby.string("foo").parse(s) }.to raise_error Parsby::ExpectationFailed
      expect(s.read).to eq "barbaz"

      s = StringIO.new "baz"
      expect { Parsby.string("foobar").parse(s) }.to raise_error Parsby::ExpectationFailed
      expect(s.read).to eq "baz"
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

    describe :restore do
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

    describe :for do
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
end
