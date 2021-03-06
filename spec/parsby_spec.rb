RSpec.describe Parsby do
  include Parsby::Combinators

  it "has a version number" do
    expect(Parsby::VERSION).not_to be nil
  end

  describe Parsby::ParsedRange do
    describe "#initialize" do
      it "takes a PosRange and a label" do
        expect(Parsby::ParsedRange.new(10, 12, "foo"))
          .to satisfy {|e| e.start == 10 }
          .and satisfy {|e| e.end == 12 }
          .and satisfy {|e| e.label == "foo" }
      end
    end

    describe "#underline" do
      it "renders a visualization of where in the current line the failure was located" do
        expect(Parsby::ParsedRange.new(5, 10, "foo").underline(Parsby::PosRange.new(0, 100)))
          .to eq "     \\---/"
      end

      it "clips the range when it's out of bounds" do
        expect(Parsby::ParsedRange.new(5, 10, "foo").underline(Parsby::PosRange.new(6, 100)))
          .to eq "---/"
      end

      it "returns empty lit when range is completely out of bounds" do
        expect(Parsby::ParsedRange.new(5, 10, "foo").underline(Parsby::PosRange.new(20, 100)))
          .to eq "<-"
      end

      it "uses | when length is 0" do
        expect(Parsby::ParsedRange.new(5, 5, "foo").underline(Parsby::PosRange.new(0, 100)))
          .to eq "     |"
      end

      it "uses V when length is 1" do
        expect(Parsby::ParsedRange.new(5, 6, "foo").underline(Parsby::PosRange.new(0, 100)))
          .to eq "     V"
      end
    end
  end

  describe Parsby::PosRange do
    describe "#initialize" do
      it "takes the start and end positions" do
        expect((
          r = Parsby::PosRange.new(10, 12)
          [r.start, r.end]
        )).to eq [10, 12]
      end
    end

    describe "#length" do
      it "is the difference of the start and end positions" do
        expect(Parsby::PosRange.new(10, 12).length).to eq 2
      end
    end

    describe "#contains?" do
      it "is true when position is within bounds" do
        expect(Parsby::PosRange.new(10, 12).contains?(11)).to eq true
        expect(Parsby::PosRange.new(10, 12).contains?(9)).to eq false
        expect(Parsby::PosRange.new(10, 12).contains?(13)).to eq false
      end

      it "is true when position is at left bound" do
        expect(Parsby::PosRange.new(10, 12).contains?(10)).to eq true
      end

      it "is false when position is at right bound" do
        expect(Parsby::PosRange.new(10, 12).contains?(12)).to eq false
      end
    end

    describe "#overlaps?" do
      it "is true when partially overlapping" do
        expect(
          Parsby::PosRange.new(10, 12).overlaps?(
            Parsby::PosRange.new(11, 13)
          )
        ).to eq true
      end

      it "is true when completely overlapping" do
        expect(
          Parsby::PosRange.new(10, 12).overlaps?(
            Parsby::PosRange.new(9, 13)
          )
        ).to eq true
        expect(
          Parsby::PosRange.new(9, 13).overlaps?(
            Parsby::PosRange.new(10, 12)
          )
        ).to eq true
      end

      it "is false when just touching a bound" do
        expect(
          Parsby::PosRange.new(10, 12).overlaps?(
            Parsby::PosRange.new(12, 13)
          )
        ).to eq false

        expect(
          Parsby::PosRange.new(12, 13).overlaps?(
            Parsby::PosRange.new(10, 12)
          )
        ).to eq false
      end

      it "is false when completely outside" do
        expect(
          Parsby::PosRange.new(10, 12).overlaps?(
            Parsby::PosRange.new(13, 14)
          )
        ).to eq false
      end
    end

    describe "#&" do
      it "returns intersection of overlapping ranges" do
        expect((
          r = Parsby::PosRange.new(10, 12) \
            & Parsby::PosRange.new(11, 13)
          [r.start, r.end]
        )).to eq [11, 12]
      end

      it "returns 0-length range when ranges are touching" do
        expect((
          r = Parsby::PosRange.new(10, 12) \
            & Parsby::PosRange.new(12, 13)
          [r.start, r.end]
        )).to eq [12, 12]
      end

      it "returns nil when ranges don't overlap" do
        expect(
          Parsby::PosRange.new(10, 12) \
            & Parsby::PosRange.new(13, 14)
        ).to eq nil
      end
    end

    describe "#length_in" do
      it "returns length of overlapping range" do
        expect(
          Parsby::PosRange.new(10, 12).length_in(
            Parsby::PosRange.new(11, 13)
          )
        ).to eq 1
      end

      it "returns 0 when ranges don't overlap" do
        expect(
          Parsby::PosRange.new(10, 12).length_in(
            Parsby::PosRange.new(13, 14)
          )
        ).to eq 0
      end
    end

    describe "#starts_inside_of?" do
      it "returns true if provided range contains our start" do
        expect(
          Parsby::PosRange.new(10, 12).starts_inside_of?(
            Parsby::PosRange.new(11, 13)
          )
        ).to eq false

        expect(
          Parsby::PosRange.new(11, 13).starts_inside_of?(
            Parsby::PosRange.new(10, 12)
          )
        ).to eq true

        expect(
          Parsby::PosRange.new(10, 13).starts_inside_of?(
            Parsby::PosRange.new(10, 13)
          )
        ).to eq true
      end
    end

    describe "#ends_inside_of?" do
      it "returns true if provided range contains our end" do
        expect(
          Parsby::PosRange.new(10, 12).ends_inside_of?(
            Parsby::PosRange.new(11, 13)
          )
        ).to eq true

        expect(
          Parsby::PosRange.new(11, 13).ends_inside_of?(
            Parsby::PosRange.new(10, 12)
          )
        ).to eq false

        expect(
          Parsby::PosRange.new(10, 13).ends_inside_of?(
            Parsby::PosRange.new(10, 13)
          )
        ).to eq true
      end
    end

    describe "#completely_left_of?" do
      it "is true only when our end comes before the provided range's start" do
        expect(
          Parsby::PosRange.new(10, 12).completely_left_of?(
            Parsby::PosRange.new(14, 15)
          )
        ).to eq true

        expect(
          Parsby::PosRange.new(10, 12).completely_left_of?(
            Parsby::PosRange.new(11, 13)
          )
        ).to eq false
      end
    end

    describe "#completely_right_of?" do
      it "is true only when our start comes after the provided range's end" do
        expect(
          Parsby::PosRange.new(14, 15).completely_right_of?(
            Parsby::PosRange.new(10, 12)
          )
        ).to eq true

        expect(
          Parsby::PosRange.new(11, 13).completely_right_of?(
            Parsby::PosRange.new(10, 12)
          )
        ).to eq false
      end
    end

    describe "#completely_inside_of?" do
      it "is true only when we start inside and end inside" do
        expect(
          Parsby::PosRange.new(10, 12).completely_inside_of?(
            Parsby::PosRange.new(9, 13)
          )
        ).to eq true

        expect(
          Parsby::PosRange.new(10, 12).completely_inside_of?(
            Parsby::PosRange.new(10, 12)
          )
        ).to eq true

        expect(
          Parsby::PosRange.new(10, 12).completely_inside_of?(
            Parsby::PosRange.new(11, 13)
          )
        ).to eq false
      end
    end

    describe "#render_in" do
      it "renders range in another range" do
        expect(
          Parsby::PosRange.new(10, 14).render_in(
            Parsby::PosRange.new(9, 16)
          )
        ).to eq " \\--/"
      end

      it "ranges of length 0 are rendered |" do
        expect(
          Parsby::PosRange.new(10, 10).render_in(
            Parsby::PosRange.new(9, 16)
          )
        ).to eq " |"
      end

      it "ranges of length 1 are rendered V" do
        expect(
          Parsby::PosRange.new(10, 11).render_in(
            Parsby::PosRange.new(9, 16)
          )
        ).to eq " V"
      end

      it "ranges of length 2 are rendered \\/" do
        expect(
          Parsby::PosRange.new(10, 12).render_in(
            Parsby::PosRange.new(9, 16)
          )
        ).to eq " \\/"
      end

      it "ranges of length 3 are rendered \\-/" do
        expect(
          Parsby::PosRange.new(10, 13).render_in(
            Parsby::PosRange.new(9, 16)
          )
        ).to eq " \\-/"
      end

      it "ranges that start before rendering range with overlap of 2 are rendered -/" do
        expect(
          Parsby::PosRange.new(10, 13).render_in(
            Parsby::PosRange.new(11, 16)
          )
        ).to eq "-/"
      end

      it "ranges that start before rendering range with overlap of 1 are rendered /" do
        expect(
          Parsby::PosRange.new(10, 13).render_in(
            Parsby::PosRange.new(12, 16)
          )
        ).to eq "/"
      end

      it "ranges that start before rendering range with overlap of 0 are rendered <-" do
        expect(
          Parsby::PosRange.new(10, 13).render_in(
            Parsby::PosRange.new(13, 16)
          )
        ).to eq "<-"

        expect(
          # This doesn't start before rendering range.
          Parsby::PosRange.new(13, 13).render_in(
            Parsby::PosRange.new(13, 16)
          )
        ).to eq "|"
      end

      it "ranges that end after rendering range with overlap of 0 are rendered ->" do
        expect(
          Parsby::PosRange.new(13, 16).render_in(
            Parsby::PosRange.new(10, 13)
          )
        ).to eq "->"
      end

      it "ranges that end after rendering range with overlap of 1 are rendered \\" do
        expect(
          Parsby::PosRange.new(12, 16).render_in(
            Parsby::PosRange.new(10, 13)
          )
        ).to eq "  \\"
      end

      it "ranges that end after rendering range with overlap of 2 are rendered \\-" do
        expect(
          Parsby::PosRange.new(11, 16).render_in(
            Parsby::PosRange.new(10, 13)
          )
        ).to eq " \\-"
      end
    end
  end

  describe Parsby::ExpectationFailed do
    describe "#initialize" do
      it "takes a context as argument" do
        expect(
          Parsby::ExpectationFailed
            .new(Parsby::Context.new("foobar"))
            .instance_eval { @ctx }
        ).to be_a Parsby::Context
      end
    end

    describe "#message" do
      def exception
        yield
      rescue => e
        e
      end

      it "displays the furthest point of error despite the last error being earlier" do
        expect(
          exception {
            (lit("foo") > spaced(lit("bar")) * 3 < eof)
              .parse("foo\nbar bar box")
          }.message
        ).to eq <<~ERROR
          line 2:
            bar bar box
                    \\-/   * failure: lit("bar")
                    |     * failure: spaced(lit("bar"))
                \\--/     *| success: spaced(lit("bar"))
            ---/        *|| success: spaced(lit("bar"))
                        \\\\|
            -------/      * failure: (spaced(lit("bar")) * 3)
            <-           *| success: lit("foo")
                         \\|
            <-            * failure: (lit("foo") > (spaced(lit("bar")) * 3))
            <-            * failure: ((lit("foo") > (spaced(lit("bar")) * 3)) < eof)
        ERROR
      end
    end
  end

  describe Parsby::Tree do
    class TreeObj
      include Parsby::Tree
      attr_reader :x

      def initialize(x)
        @x = x
      end

      def whole_name
        self_and_ancestors.reverse.map(&:x).join(".")
      end
    end

    def tree(e, &b)
      TreeObj.new(e).tap do |t|
        t.tap(&b) if b
      end
    end

    let :std_tree do
      tree("root") { |t|
        t.<< *3.times.map { |i|
          tree("a#{i}") { |t|
            t.<< *3.times.map { |i|
              tree("b#{i}") { |t|
                t.<< *3.times.map { |i|
                  tree("c#{i}")
                }
              }
            }
          }
        }
      }
    end

    describe "#children" do
      it "returns the children of the current node" do
        expect(tree("foo").children).to eq []
        expect(tree("foo") {|t| t << tree("bar") }.children.map(&:x)).to eq ["bar"]
      end
    end

    describe "#dup" do
      it "duplicates self" do
        expect(tree("foo").dup.x).to eq "foo"
        expect((t = tree("foo"); t.dup.object_id == t.object_id)).to eq false
      end

      it "duplicates children" do
        expect((
          t0 = tree("foo") { |t|
            t << tree("foo_bar")
            t << tree("foo_baz")
          }
          t1 = t0.dup
          [
            t1.children.map(&:x),
            t1.children.map(&:object_id) == t0.children.map(&:object_id),
          ]
        )).to eq [
          ["foo_bar", "foo_baz"],
          false,
        ]
      end

      it "redirects parents of children" do
        expect((
          t0 = tree("foo") { |t|
            t << tree("foo_bar")
          }
          t1 = t0.dup
          t1.children.first.parent == t1
        )).to eq true
      end

      it "duplicates parents" do
        expect((
          t0 = tree("foo") { |t|
            t << tree("foo_bar")
          }.children.first
          t1 = t0.dup
          [t1.parent.x, t1.parent.object_id == t0.parent.object_id ]
        )).to eq ["foo", false]
      end

      it "duplicates siblings" do
        expect((
          t0 = tree("foo") { |t|
            t << tree("foo_bar")
            t << tree("foo_baz")
          }.children.first
          t1 = t0.dup
          [
            t1.parent.children.last.x,
            t1.parent.children.last.object_id == t0.parent.children.last.object_id,
          ]
        )).to eq ["foo_baz", false]
      end
    end

    describe "#flatten" do
      it "flattens the tree into an array" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar") { |t|
              t << tree("foo_bar_baz")
            }
            t << tree("foo_baz")
          }.flatten.map(&:x)
        ).to eq ["foo", "foo_bar", "foo_bar_baz", "foo_baz"]
      end

      it "doesn't include ancestors" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar") { |t|
              t << tree("foo_bar_baz")
            }
            t << tree("foo_baz")
          }.children.first.flatten.map(&:x)
        ).to eq ["foo_bar", "foo_bar_baz"]
      end
    end

    describe "#<<" do
      it "appends right tree to list of children of left tree" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar")
            t << tree("foo_baz")
          }.children.map(&:x)
        ).to eq ["foo_bar", "foo_baz"]
      end

      it "sets parent of right tree to be the left tree" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar")
          }.children[0].parent.x
        ).to eq "foo"
      end
    end

    describe "#sibling_index" do
      it "returns the index where the current node is situated in its parent's children array" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar")
            t << tree("foo_baz")
          }.children[1].sibling_index
        ).to eq 1
      end

      it "returns nil for a root node" do
        expect(
          tree("foo").sibling_index
        ).to eq nil
      end
    end

    describe "#sibling_reverse_index" do
      it "returns index of self among siblings in reverse order" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar")
            t << tree("foo_baz")
          }.children[1].sibling_reverse_index
        ).to eq 0
      end

      it "returns nil for a root node" do
        expect(
          tree("foo").sibling_reverse_index
        ).to eq nil
      end
    end

    describe "#right_uncles" do
      it "returns the sum of the number of latter siblings among all ancestors (uncles) and self (non-uncles)" do
        expect(
          std_tree.get([1,1,1]).right_uncles
        ).to eq 3
      end
    end

    describe "#get" do
      it "returns child at the given path" do
        expect(
          std_tree.children[1].get([1,1]).path
        ).to eq [1,1,1]
      end
    end

    describe "#each" do
      it "runs block for self and descendant nodes" do
        expect((
          r = []
          std_tree.get([1,1]).each do |t|
            r << t.whole_name
          end
          r
        )).to eq ["root.a1.b1", "root.a1.b1.c0", "root.a1.b1.c1", "root.a1.b1.c2"]
      end
    end

    describe "#select" do
      it "selects among self and descendants according to block" do
        expect(
          std_tree.select {|t| t.x =~ /\Aa/}.map(&:whole_name)
        ).to eq %w(root.a0 root.a1 root.a2)
      end
    end

    describe "#select_paths" do
      it "selects like #select, but returning paths relative to current node" do
        expect(
          std_tree.children[1].select_paths {|t| t.x =~ /\Ab/}
        ).to eq [[0], [1], [2]]
      end
    end

    describe "#right_tree_slice" do
      it "returns a slice of a right-justified rendition of the tree for the current node" do
        expect(
          std_tree.get([1,1,1]).right_tree_slice
        ).to eq "*|||"
      end
    end

    describe "#trim_to_just!" do
      it "removes all descendants except for those specified and their ancestors up to self" do
        expect(
          std_tree.children[1]
            .trim_to_just!([1, 2], [2])
            .select {true}.map {|n| n.whole_name + "\n"}.join
        ).to eq <<~EOF
          root.a1
          root.a1.b0
          root.a1.b1
          root.a1.b1.c0
          root.a1.b1.c1
          root.a1.b1.c2
          root.a1.b2
        EOF
      end
    end

    describe "#splice_self!" do
      it "removes self from tree, replacing itself among its siblings with its children" do
        expect {
          std_tree.children[1].splice_self!
        }.to change { std_tree.children.map(&:x) }
          .from(%w(a0 a1 a2))
          .to(%w(a0 b0 b1 b2 a2))
      end
    end

    describe "#splice" do
      it "returns dup'ed tree where children are replaced with indicated descendants" do
        expect(
          std_tree.children[1].splice([1,1], [2,2]).children.map(&:whole_name)
        ).to eq %w(root.a1.c1 root.a1.c2)
      end
    end

    describe "#splice!" do
      it "destructively replaces children with indicated descendants" do
        expect((
          std_tree.children[1].splice!([1,1], [2,2])
          std_tree.children[1].children.map(&:whole_name)
        )).to eq %w(root.a1.c1 root.a1.c2)
      end
    end

    describe "#path" do
      it "returns the path to the current node from the root" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar")
            t << tree("foo_baz") { |t|
              t << tree("foo_baz_taz") { |t|
                t << tree("foo_baz_taz_mak")
              }
            }
          }.children[1].children[0].children[0].path
        ).to eq [1, 0, 0]
      end

      it "returns an empty list for the root node" do
        expect(
          tree("foo").path
        ).to eq []
      end
    end

    describe "#root" do
      it "returns the root of a tree" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar") { |t|
              t << tree("foo_bar_baz")
            }
            t << tree("foo_baz")
          }.children.first.children.first.root.x
        ).to eq "foo"

        expect(
          tree("foo").root.x
        ).to eq "foo"
      end
    end

    describe "#self_and_ancestors" do
      it "returns list of self and ancestors" do
        expect(
          tree("foo") { |t|
            t << tree("foo_bar") { |t|
              t << tree("foo_bar_baz")
            }
            t << tree("foo_baz")
          }.children.first.children.first.self_and_ancestors.map(&:x)
        ).to eq ["foo_bar_baz", "foo_bar", "foo"]
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

      it "doesn't use backup when it doesn't need to" do
        io = StringIO.new "foo"
        bio = Parsby::BackedIO.new io
        expect(bio).to_not receive(:backup)
        bio.pos
      end

      it "uses backup when using the io's pos fails for being a pipe" do
        piped "foo" do |io|
          bio = Parsby::BackedIO.new io
          allow(io).to receive(:pos) { raise Errno::ESPIPE }
          allow(bio).to receive(:backup) { Parsby::Backup.new("foo") }
          expect(io).to receive(:pos)
          expect(bio).to receive(:backup)
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
            [r1, r2, backup.back]
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
          end.instance_eval { @backup.back }
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
      it "accepts a lit as argument, turning it into a StringIO" do
        expect(Parsby::BackedIO.new("foo").instance_eval { @io })
          .to be_a StringIO
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
      expect(Parsby.new.label).to eq "unknown"
    end

    it "takes block that provides a BackedIO as argument, and which result is the result of #parse" do
      expect(Parsby.new {|c| c.class}.parse "foo").to eq Parsby::Context
      expect(Parsby.new {|c| c.bio.read(2) }.parse "foo").to eq "fo"
    end
  end

  describe "#parse" do
    it "accepts strings" do
      expect(lit("foo").parse("foo")).to eq "foo"
    end

    it "accepts IO objects" do
      expect(lit("foo").parse IO.pipe.tap {|(_, w)| w.write "foo"; w.close }.first)
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
      expect(Parsby.new.tap {|p| p.label = :foo}.label.to_s).to eq "foo"
    end
  end

  describe "#label" do
    it "defaults to unknown token" do
      expect(Parsby.new.label).to eq "unknown"
    end
  end

  describe "#*" do
    it "p * n parses p n times and returns the results in an array" do
      expect((lit("foo") * 2).parse "foofoo").to eq ["foo", "foo"]
    end

    it "fails if it can't parse the number of times specified" do
      expect { (lit("foo") * 3).parse "foofoo" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#<<" do
    it "appends right operand to list result of left operand" do
      expect((many(lit("foo")) << lit("bar")).parse "foofoobar")
        .to eq ["foo", "foo", "bar"]
    end
  end

  describe "#+" do
    it "joins the results with +" do
      expect((lit("foo") + lit("bar")).parse "foobar").to eq "foobar"
    end
  end

  describe "#|" do
    it "tries second operand if first one fails" do
      expect((lit("foo") | lit("bar")).parse "bar").to eq "bar"
      expect { (lit("foo") | lit("bar")).parse "baz" }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#<" do
    it "parses left operand then right operand, and returns the result of left" do
      expect((lit("foo") < lit("bar")).parse "foobar").to eq "foo"
    end
  end

  describe "#>" do
    it "parses left operand then right operand, and returns the result of right" do
      expect((lit("foo") > lit("bar")).parse "foobar").to eq "bar"
    end
  end

  describe "#%" do
    it "sets the label of the parser" do
      expect((lit("foo") % "bar").label).to eq "bar"
    end
  end

  describe "#that_fails" do
    it "tries parser argument; if argument fails, it parses with receiver; if argument succeeds, then it fails" do
      expect(decimal.that_fails(lit("10")).parse("34")).to eq 34
      expect { decimal.that_fails(lit("10")).parse("10") }
        .to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#fmap" do
    it "permits working with the value \"inside\" the parser, like map does with array" do
      expect(decimal.fmap {|x| x + 1}.parse("3")).to eq 4
    end
  end

  describe "#then" do
    it "provides block with result of left parser" do
      expect((
        x = nil
        lit("foo").then {|r| x = r; pure nil }.parse "foo"
        x
      )).to eq "foo"
    end

    it "results in the result of the parser returned from the block" do
      expect(
        lit("foo").then {|r| lit("bar") }.parse "foobar"
      ).to eq "bar"
    end
  end
end
