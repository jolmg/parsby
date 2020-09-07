require "parsby/version"
require "parsby/combinators"

class Parsby
  include Combinators

  class Error < StandardError; end

  class PosRange
    attr_accessor :start, :end

    def initialize(pos_start, pos_end)
      @start = pos_start
      @end = pos_end
    end

    def length
      @end - @start
    end

    def length_in(range)
      (self & range)&.length || 0
    end

    # Intersection of the two ranges.
    def &(range)
      return nil unless overlaps? range
      PosRange.new [@start, range.start].max, [@end, range.end].min
    end

    def overlaps?(range)
      !(completely_left_of?(range) || completely_right_of?(range))
    end

    def completely_left_of?(range)
      @end <= range.start
    end

    def completely_right_of?(range)
      @start >= range.end
    end

    def contains?(pos)
      @start <= pos && pos <= @end
    end

    def starts_inside_of?(range)
      range.contains? @start
    end

    def ends_inside_of?(range)
      range.contains? @end
    end

    def completely_inside_of?(range)
      starts_inside_of?(range) && ends_inside_of?(range)
    end

    def render_in(line_range)
      return "<-" if completely_left_of? line_range
      return "->" if completely_right_of? line_range
      indentation = " " * [0, start - line_range.start].max
      r = "-" * length_in(line_range)
      r[0] = "\\" if starts_inside_of? line_range
      r[-1] = "/" if ends_inside_of? line_range
      r[0] = "|" if length_in(line_range) == 0
      r[0] = "V" if length_in(line_range) == 1 && completely_inside_of?(line_range)
      indentation + r
    end
  end

  module Tree
    attr_accessor :parent, :is_splice_end
    attr_writer :children

    def splice_to_ends!
      ends = select_paths(&:is_splice_end).each do |path|
        get(path).is_splice_end = false
      end
      splice!(*ends)
    end

    def children
      @children ||= []
    end

    def <<(*ts)
      ts.each do |t|
        t.parent = self
        children << t
      end
    end

    def root
      if parent == nil
        self 
      else
        parent.root
      end
    end

    def sibling_reverse_index
      parent&.children&.reverse&.index self
    end

    def sibling_index
      parent&.children&.index self
    end

    def flatten
      [self, *children.map(&:flatten).flatten]
    end

    alias_method :self_and_descendants, :flatten

    def path
      [*parent&.path, *sibling_index]
    end

    def each(&b)
      b.call self
      children.each {|c| c.each(&b) }
      self
    end

    def right_uncles
      if parent
        sibling_reverse_index + parent.right_uncles
      else
        0
      end
    end

    def right_tree_slice
      "*" + "|" * right_uncles
    end

    def dup(currently_descending: false)
      self_path = path
      if parent && !currently_descending
        root.dup.get self_path
      else
        super().tap do |d|
          d.children = d.children.map do |c|
            c.dup(currently_descending: true).tap do |dc|
              dc.parent = d
            end
          end
        end
      end
    end

    def splice_self!
      idx = sibling_index
      parent.children.delete_at(idx)
      parent.children.insert(idx, *children.each {|c| c.parent = parent })
      parent
    end

    def splice!(*paths)
      self.children = paths
        .map {|p| get(p)&.tap {|d| d.parent = self } }
        .reject(&:nil?)
      self
    end

    def splice(*paths)
      dup.splice!(*paths)
    end

    def trim_to_just!(*paths)
      self.children = paths
        .group_by(&:first)
        .to_a
        .reject {|(i, _)| i.nil? }
        .map do |(child_index, child_paths)|
          if child_index
            child_subpaths = child_paths.map {|p| p.drop 1 }
            children[child_index].trim_to_just!(*child_subpaths)
          end
        end
      self
    end

    def select(&b)
      r = []
      each do |n|
        if b.call n
          r << n
        end
      end
      r
    end

    def select_paths(&b)
      root_path = path
      select(&b).map do |n|
        n.path.drop root_path.length
      end
    end

    def get(path)
      return self if path.empty?
      idx, *sub_path = path
      child = children[idx]
      child&.get sub_path
    end

    def self_and_ancestors
      [self, *parent&.self_and_ancestors]
    end
  end

  class ParsedRange < PosRange
    attr_reader :label, :is_splice_end
    attr_accessor :failed

    include Tree

    # Initialize failure with starting position, ending position, and
    # label of what was expected.
    def initialize(pos_start, pos_end, label, is_splice_end = false)
      @label = label
      @is_splice_end = is_splice_end
      super(pos_start, pos_end)
    end

    alias_method :underline, :render_in
  end

  class ExpectationFailed < Error
    attr_reader :ctx

    # Initializes an ExpectationFailed from a backed_io and an optional
    # expectation with which to start the list of expectations that lead to
    # this failure.
    def initialize(ctx)
      @ctx = ctx
    end

    INDENTATION = 2

    # The message of the exception. It's the current line, with a kind-of
    # backtrace showing the failed expectations with a visualization of
    # their range in the current line.
    def message
      parsed_range = ctx.furthest_parsed_range
      other_ranges = ctx.parsed_ranges.flatten.select do |range|
        range.start == parsed_range.start && range != parsed_range
      end
      failure_tree = parsed_range.dup.root.trim_to_just!(*[parsed_range, *other_ranges].map(&:path))
      ctx.bio.with_saved_pos do
        ctx.bio.seek parsed_range.start
        r = "line #{ctx.bio.line_number}:\n"
        r << "#{" " * INDENTATION}#{ctx.bio.current_line}\n"
        line_range = ctx.bio.current_line_range
        tree_lines = []
        max_tree_slice_length = failure_tree.flatten.map {|t| t.right_tree_slice.length }.max
        prev_slice_length = nil
        failure_tree.each do |range|
          line = ""
          line << " " * INDENTATION
          line << range.underline(line_range)
          line << " " * (ctx.bio.current_line.length + INDENTATION - line.length)
          this_slice_length = range.right_tree_slice.length
          if prev_slice_length && this_slice_length > prev_slice_length
            fork_line = line.gsub(/./, " ")
            fork_line << " "
            i = 0
            fork_line << range.right_tree_slice.rjust(max_tree_slice_length).gsub(/[*|]/) do |c|
              i += 1
              if i <= this_slice_length - prev_slice_length
                "\\"
              else
                c 
              end
            end
            fork_line << "\n"
          else
            fork_line = ""
          end
          prev_slice_length = this_slice_length
          line << " #{range.right_tree_slice.rjust(max_tree_slice_length)}"
          line << " #{range.failed ? "failure" : "success"}: #{range.label}"
          line << "\n"
          tree_lines << fork_line << line
        end
        r << tree_lines.reverse.join
        r
      end
    end
  end

  class Token
    attr_reader :name

    # Makes a token with the given name.
    def initialize(name)
      @name = name
    end

    # Renders token name by surrounding it in angle brackets.
    def to_s
      "<#{name}>"
    end

    # Compare tokens
    def ==(t)
      t.is_a?(self.class) && t.name == name
    end

    # Flipped version of Parsby#%, so you can specify the token of a parser
    # at the beginning of a parser expression.
    def %(p)
      p % self
    end
  end

  class Backup < StringIO
    def with_saved_pos(&b)
      saved = pos
      b.call saved
    ensure
      seek saved
    end

    def all
      with_saved_pos do
        seek 0
        read
      end
    end

    alias_method :back_size, :pos

    def back(n = back_size)
      with_saved_pos do |saved|
        seek -n, IO::SEEK_CUR
        read n
      end
    end

    def rest_of_line
      with_saved_pos { readline }
    rescue EOFError
      ""
    end

    def back_lines
      (back + rest_of_line).lines
    end

    def col
      back[/(?<=\A|\n).*\z/].length
    end

    def current_line
      with_saved_pos do
        seek(-col, IO::SEEK_CUR)
        readline.chomp
      end
    end
  end

  class BackedIO
    # Initializes a BackedIO out of the provided IO object or String. The
    # String will be turned into an IO using StringIO.
    def initialize(io)
      io = StringIO.new io if io.is_a? String
      @io = io
      @backup = Backup.new
    end

    # Makes a new BackedIO out of the provided IO, calls the provided
    # blocked and restores the IO on an exception.
    def self.for(io, &b)
      bio = new io
      begin
        b.call bio
      rescue
        bio.restore
        raise
      end
    end

    # Similar to BackedIO.for, but it always restores the IO, even when
    # there's no exception.
    def self.peek(io, &b)
      self.for io do |bio|
        begin
          b.call bio
        ensure
          bio.restore
        end
      end
    end

    def with_saved_pos(&b)
      saved = pos
      begin
        b.call saved
      ensure
        restore_to saved
      end
    end

    # Like #read, but without consuming.
    def peek(*args)
      with_saved_pos { read(*args) }
    end

    # Delegates pos to inner io, and works around pipes' inability to
    # return pos by getting the length of the innermost BackedIO.
    def pos
      @io.pos
    rescue Errno::ESPIPE
      backup.pos
    end

    # Returns line number of current line. This is 1-indexed.
    def line_number
      lines_read.length
    end

    def seek(amount, whence = IO::SEEK_SET)
      if whence == IO::SEEK_END
        read
        restore(-amount)
        return
      end
      new_pos = case whence
      when IO::SEEK_SET
        amount
      when IO::SEEK_CUR
        pos + amount
      end
      if new_pos > pos
        read new_pos - pos
      else
        restore_to new_pos
      end
    end

    # pos == current_line_pos + col. This is needed to convert a pos to a
    # col.
    def current_line_pos
      pos - col
    end

    def col
      backup.col
    end

    def current_line_range
      start = current_line_pos
      PosRange.new start, start + current_line.length
    end

    def load_rest_of_line
      with_saved_pos { readline }
    end

    def lines_read
      load_rest_of_line
      backup.back_lines.map(&:chomp)
    end

    # Returns current line, including what's to come from #read, without
    # consuming input.
    def current_line
      load_rest_of_line
      backup.current_line
    end

    # Restore n chars from the backup.
    def restore(n = backup.back_size)
      # Handle negatives in consideration of #with_saved_pos.
      if n < 0
        read(-n)
      else
        backup.back(n).chars.reverse.each {|c| ungetc c}
      end
      nil
    end

    def restore_to(prev_pos)
      restore(pos - prev_pos)
    end

    # This is to provide transparent delegation to methods of underlying
    # IO.
    def method_missing(m, *args, &b)
      @io.send(m, *args, &b)
    end

    def readline(*args)
      @io.readline(*args).tap {|r| backup.write r unless r.nil? }
    end

    # Reads from underlying IO and backs it up.
    def read(*args)
      @io.read(*args).tap {|r| backup.write r unless r.nil? }
    end

    # Pass to underlying IO's ungetc and discard a part of the same length
    # from the backup. As specified with different IO classes, the argument
    # should be a single character. To restore from the backup, use
    # #restore.
    def ungetc(c)
      # Though c is supposed to be a single character, as specified by the
      # ungetc of different IO objects, let's not assume that when
      # adjusting the backup.
      backup.seek(-c.length, IO::SEEK_CUR)
      @io.ungetc(c)
    end

    private

    def backup
      @backup
    end
  end

  class Context
    attr_reader :bio
    attr_accessor :parsed_ranges

    def initialize(io)
      @bio = BackedIO.new io
      @failures = []
    end

    def furthest_parsed_range
      parsed_ranges.flatten.max_by(&:start)
    end
  end

  # The parser's label. It's an "unknown" token by default.
  def label
    @label || Token.new("unknown")
  end

  # Assign label to parser. If given a symbol, it'll be turned into a
  # Parsby::Token.
  def label=(name)
    @label = name.is_a?(Symbol) ? Token.new(name) : name
  end

  # Initialize parser with optional label argument, and parsing block. The
  # parsing block is given an IO as argument, and its result is the result
  # when parsing.
  def initialize(label = nil, splicing: nil, should_splice_self: false, &b)
    self.label = label if label
    @splicing = splicing
    @should_splice_self = should_splice_self
    @parser = b
  end

  attr_accessor :splicing

  # Parse a String or IO object.
  def parse(src)
    ctx = src.is_a?(Context) ? src : Context.new(src)
    parsed_range = ParsedRange.new(ctx.bio.pos, ctx.bio.pos, label, is_splice_end)
    ctx.parsed_ranges << parsed_range if ctx.parsed_ranges
    ctx.parsed_ranges = parsed_range
    begin
      r = @parser.call ctx
    rescue ExpectationFailed => e
      ctx.parsed_ranges.end = ctx.bio.pos
      ctx.parsed_ranges.failed = true
      ctx.bio.restore_to ctx.parsed_ranges.start
      raise
    else
      ctx.parsed_ranges.end = ctx.bio.pos
      r
    ensure
      if splicing
        parsed_range.splice!(*splicing)
      end
      if is_splice_start
        parsed_range.splice_to_ends!
      end
      # Keep the root one for use in ExceptionFailed#message
      if ctx.parsed_ranges.parent
        ctx.parsed_ranges = ctx.parsed_ranges.parent
        parsed_range.splice_self! if should_splice_self
      end
    end
  end

  # Parses without consuming input.
  def peek(src)
    ctx = src.is_a?(Context) ? src : Context.new(src)
    starting_pos = ctx.bio.pos
    begin
      parse ctx
    ensure
      ctx.bio.restore_to starting_pos
    end
  end

  # <tt>x | y</tt> tries y if x fails.
  def |(p)
    Parsby.new "(#{self.label} | #{p.label})" do |c|
      begin
        parse c
      rescue Error
        p.parse c
      end
    end
  end

  # x < y runs parser x then y and returns x.
  def <(p)
    Parsby.new "(#{label} < #{p.label})" do |c|
      r = parse c
      p.parse c
      r
    end
  end

  # This is useful for the difference in precedence. With - you can do
  #
  #   x - y + z
  #
  # and skip the parentheses needed when using <
  #
  #   (x < y) + z
  alias_method :-, :<

  # x > y runs parser x then y and returns y.
  def >(p)
    Parsby.new "(#{label} > #{p.label})" do |c|
      parse c
      p.parse c
    end
  end

  attr_accessor :should_splice_self, :is_splice_start, :is_splice_end

  def ~
    @should_splice_self = true
    self
  end

  def -@
    @is_splice_start = true
    self
  end

  def +@
    @is_splice_end = true
    self
  end

  # p * n, runs parser p n times, grouping results in an array.
  def *(n)
    Parsby.new "(#{label} * #{n})" do |c|
      n.times.map { parse c }
    end
  end

  # x + y does + on the results of x and y. This is mostly meant to be used
  # with arrays, but it would work with numbers and strings too.
  def +(p)
    group(self, p)
      .fmap {|(x, y)| x + y }
      .tap {|r| r.label = "(#{label} + #{p.label})" }
  end

  # xs << x appends result of parser x to list result of parser xs.
  def <<(p)
    Parsby.new "(#{label} << #{p.label})" do |c|
      x = parse c
      y = p.parse c
      # like x << y, but without modifying x.
      x + [y]
    end
  end

  # Set the label and return self.
  def %(name)
    self.label = name
    self
  end

  # Like map for arrays, this lets you work with the value "inside" the
  # parser, i.e. the result.
  #
  # Example:
  #
  #   decimal.fmap {|x| x + 1}.parse("2")
  #   => 3
  def fmap(&b)
    Parsby.new "#{label}.fmap" do |c|
      b.call parse c
    end
  end

  # Pass result of self parser to block to construct the next parser.
  #
  # For example, instead of writing:
  #
  #   Parsby.new do |c|
  #     x = foo.parse c
  #     bar(x).parse c
  #   end
  #
  # you can write:
  #
  #   foo.then {|x| bar x }
  #
  # This is analogous to Parsec's >>= operator in Haskell, where you could
  # write:
  #
  #   foo >>= bar
  def then(&b)
    Parsby.new "#{label}.then" do |c|
      b.call(parse(c)).parse(c)
    end
  end

  # <tt>x.that_fails(y)</tt> will try <tt>y</tt>, fail if <tt>y</tt>
  # succeeds, or parse with <tt>x</tt> if <tt>y</tt>
  # fails.
  #
  # Example:
  #
  #   decimal.that_fails(string("10")).parse "3"
  #   => 3
  #   decimal.that_fails(string("10")).parse "10"
  #   Parsby::ExpectationFailed: line 1:
  #     10
  #     \/ expected: (not "10")
  def that_fails(p)
    Parsby.new "#{label}.that_fails(#{p.label})" do |c|
      orig_pos = c.bio.pos
      begin
        r = p.parse c.bio
      rescue Error
        c.bio.restore_to orig_pos
        parse c.bio
      else
        raise ExpectationFailed.new c
      end
    end
  end

  alias_method :that_fail, :that_fails
end
