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
      @end < range.start
    end

    def completely_right_of?(range)
      @start > range.end
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

  class Failure
    attr_reader :range, :label

    # Initialize failure with starting position, ending position, and
    # label of what was expected.
    def initialize(range, label)
      @range = range
      @label = label
    end

    def underline(line_range)
      range.render_in line_range
    end
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
      failure_pos = ctx.furthest_failure.range.start
      ctx.bio.with_saved_pos do
        ctx.bio.seek failure_pos
        r = "line #{ctx.bio.line_number}:\n"
        r << "#{" " * INDENTATION}#{ctx.bio.current_line}\n"
        line_range = ctx.bio.current_line_range
        ctx.failures.select {|f| f.range.overlaps? line_range }.each do |f|
          r << " " * INDENTATION
          r << f.underline(line_range)
          r << " expected: #{f.label}"
          r << "\n"
        end
        r
      end
    end
  end

  class Tree
    attr_reader :element, :children
    attr_accessor :parent

    def initialize(element)
      @element = element
      @children = []
    end

    def <<(t)
      t.parent = self
      children << t
    end

    def root
      if parent == nil
        self 
      else
        parent.root
      end
    end

    def flatten
      [self, *children.map(&:flatten).flatten]
    end

    def self_and_ancestors
      [self, *parent&.self_and_ancestors]
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
    attr_reader :bio, :failures

    def initialize(io)
      @bio = BackedIO.new io
      @failures = []
    end

    def furthest_failure
      failures.max_by {|f| f.range.start }
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
  def initialize(label = nil, &b)
    self.label = label if label
    @parser = b
  end

  # Parse a String or IO object.
  def parse(src)
    ctx = src.is_a?(Context) ? src : Context.new(src)
    starting_pos = ctx.bio.pos
    begin
      @parser.call ctx
    rescue ExpectationFailed => e
      ending_pos = ctx.bio.pos
      ctx.failures << Failure.new(PosRange.new(starting_pos, ending_pos), label)
      ctx.bio.restore_to starting_pos
      raise
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
    Parsby.new self.label do |c|
      b.call parse c
    end
  end

  # Allows you to modify the exception to add information when defining the
  # parser via combinators.
  def on_catch(&b)
    Parsby.new do |c|
      begin
        parse c
      rescue Error => e
        b.call e
        raise
      end
    end
  end

  # Peeks to see whether parser would succeed if applied.
  def would_succeed(c)
    begin
      peek c
    rescue Error
      false
    else
      true
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
