require "parsby/version"
require "parsby/combinators"

class Parsby
  include Combinators

  class Error < StandardError; end

  class Failure
    attr_accessor :starts_at, :ends_at, :label

    # Initialize failure with starting position, ending position, and
    # label of what was expected.
    def initialize(starts_at, ends_at, label)
      @starts_at = starts_at
      @ends_at = ends_at
      @label = label
    end

    # Length of range. This is not considering current line bounds.
    def length
      @length ||= ends_at - starts_at
    end

    # col on current line where it start. This is negative when on a
    # previous line.
    def starts_at_col(current_line_pos)
      starts_at - current_line_pos
    end

    # col on current line where it ends. This is negative when on a
    # previous line.
    def ends_at_col(current_line_pos)
      ends_at - current_line_pos
    end

    # Returns an underline representation of the expectation, for the line
    # where a failure was raised.
    def underline(current_line_pos)
      if ends_at_col(current_line_pos) < 0
        # Range is completely out of here. This is possible if we do
        #
        #   foo | multiline_thing
        #
        # The | would fail where multiline_thing started.
        ""
      elsif starts_at_col(current_line_pos) < 0
        # Range starts on a previous line.
        "#{"-" * (ends_at - current_line_pos - 1)}/"
      else
        case length
        when 0
          "|"
        when 1
          "V"
        when 2
          "\\/"
        else
          # The whole thing is on the current line.
          "\\#{"-" * (length - 2)}/"
        end
      end
    end
  end

  class ExpectationFailed < Error
    attr_reader :ctx

    # Initializes an ExpectationFailure from a backed_io and an optional
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
      r = "line #{ctx.bio.line_number}:\n"
      r << "#{" " * INDENTATION}#{ctx.bio.current_line}\n"
      ctx.failures.each do |f|
        r << " " * (INDENTATION + [f.starts_at_col(ctx.bio.current_line_pos), 0].max)
        r << f.underline(ctx.bio.current_line_pos)
        r << " expected: #{f.label}"
        r << "\n"
      end
      r
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

  class BackedIO
    # Initializes a BackedIO out of the provided IO object or String. The
    # String will be turned into an IO using StringIO.
    def initialize(io)
      io = StringIO.new io if io.is_a? String
      @io = io
      @backup = ""
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

    # Like #read, but without consuming.
    def peek(*args)
      self.class.peek self do |bio|
        bio.read(*args)
      end
    end

    # Returns the backup from the innermost BackedIO
    def grand_backup
      return @io.grand_backup if @io.is_a? BackedIO
      @backup
    end

    # Delegates pos to inner io, and works around pipes' inability to
    # return pos by getting the length of the innermost BackedIO.
    def pos
      @io.pos
    rescue Errno::ESPIPE
      grand_backup.length
    end

    # Position in current_line. current_line[col] == peek(1). This is
    # 0-indexed.
    def col
      back_context.length
    end

    # Returns line number of current line. This is 1-indexed.
    def line_number
      lines_read.length
    end

    # pos == current_line_pos + col. This is needed to convert a pos to a
    # col.
    def current_line_pos
      pos - col
    end

    def lines_read
      (grand_backup + forward_context).lines.map(&:chomp)
    end

    # The part of the current line from the current position backward.
    def back_context
      grand_backup[/(?<=\A|\n).*\z/]
    end

    # The part of the current line from the current position forward.
    def forward_context
      self.class.peek self do |bio|
        r = ""
        begin
          x = bio.read(1)
          r << x.to_s
        end while x != "\n" && !x.nil?
        r.chomp
      end
    end

    # Returns current (chomped) line, including what's to come from #read,
    # without consuming input.
    def current_line
      back_context + forward_context
    end

    # Restore n chars from the backup.
    def restore(n = @backup.length)
      n.times { ungetc @backup[-1] }
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

    # Reads from underlying IO and backs it up.
    def read(*args)
      @io.read(*args).tap {|r| @backup << r unless r.nil? }
    end

    # Pass to underlying IO's ungetc and discard a part of the same length
    # from the backup. As specified with different IO classes, the argument
    # should be a single character. To restore from the backup, use
    # #restore.
    def ungetc(c)
      # Though c is supposed to be a single character, as specified by the
      # ungetc of different IO objects, let's not assume that when
      # adjusting the backup.
      @backup.slice! @backup.length - c.length
      @io.ungetc(c)
    end
  end

  class Context
    attr_reader :bio, :failures

    def initialize(io)
      @bio = BackedIO.new io
      @failures = []
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
      ctx.failures << Failure.new(starting_pos, ending_pos, label)
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
