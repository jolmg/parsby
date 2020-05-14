RSpec.describe Parsby do
  it "has a version number" do
    expect(Parsby::VERSION).not_to be nil
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
    end

    describe :for do
      it "works when nested" do
        Parsby::BackedIO.for r do |br1|
          expect(br1.read 3).to eq "foo"

          Parsby::BackedIO.for br1 do |br2|
            expect(br2.read 3).to eq "bar"
            br2.restore
            expect(br2.read 3).to eq "bar"
            br2.restore
          end

          expect(br1.read 6).to eq "barbaz"
          br1.restore
          expect(br1.read 9).to eq "foobarbaz"
        end
      end
    end
  end
end
