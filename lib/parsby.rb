require "parsby/version"
require "parsby/combinators"

class Parsby
  extend Combinators

  class Error < StandardError; end

  class Expectation
    attr_reader :at, :label

    # Create an expectation at the given location with the given label.
    def initialize(at, label)
      @at = at
      @label = label
    end

    # Returns an underline representation of the expectation, for the line
    # where a failure was raised.
    #
    # FIXME: This depends on changes to ExpectationFailed that haven't been
    # made.
    def underline(failure)
      at_col = at - failure.bio.current_line_pos
      length = failure.at_col - at_col
      case length
      when 1
        "V"
      when 2
        "\\/"
      else
        "\\#{"-" * (length - 2)}/"
      end
    end
  end

  class ExpectationFailed < Error
    attr_accessor :at, :expected, :actual

    # Makes an exception with the optional keyword arguments :expected,
    # :actual, and manditory :at.
    def initialize(at: nil, expected: nil, actual: nil)
      @at = at
      @expected = Array(expected)
      @actual = actual
    end

    # Renders the exception message using the options :expected, :actual,
    # and :at. :action is #inspect'ed before interpolation.
    def message
      parts = []
      parts << "expected #{opts[:expected]}" if opts[:expected]
      parts << "actual #{opts[:actual].inspect}" if opts[:actual]
      parts << "at #{opts[:at]}"
      parts.join(", ")
    end

    # For backwards compatibility with other code, while this class is
    # changed to provide more information to the user.
    def opts
      h = { at: at }
      h[:actual] = actual if actual
      h[:expected] = expected.last if expected
      h
    end

    # For backwards compatibility with other code, while this class is
    # changed to provide more information to the user.
    def opts=(at: at, expected: expected, actual: actual)
      @at = at
      @expected += Array(expected)
      @actual = actual
    end

    # I'd rather keep things immutable, but part of the original backtrace
    # is lost if we use a new one.
    def modify!(opts)
      self.opts = self.opts.merge opts
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

    # Position in current_line. current_line[col] == peek(1)
    def col
      back_context.length
    end

    # pos == current_line_pos + col. This is needed to convert a pos to a
    # col, to display a cursor given an Expectation#at.
    def current_line_pos
      pos - back_context.length
    end

    # The part of the current line, from the current position backward. It
    # stops at MAX_CONTEXT chars if it hasn't found EOL or EOF by then and
    # adds an ellipsis if that's the case.
    def back_context
      return @io.back_context if @io.is_a? BackedIO
      @backup[/(?<=\A|\n).*\z/]
    end

    # The part of the current line, from the current position forward. It
    # stops at MAX_CONTEXT chars if it hasn't found EOL or EOF by then and
    # adds an ellipsis if that's the case.
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
    # without consuming input. It has a max length of MAX_CONTEXT on each
    # side of current position.
    def current_line
      back_context + forward_context
    end

    # Restore n chars from the backup.
    def restore(n = @backup.length)
      n.times { ungetc @backup[-1] }
      nil
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
  def parse(io)
    BackedIO.for io do |bio|
      begin
        @parser.call bio
      rescue ExpectationFailed => e
        # Use the instance variable instead of the reader since the reader
        # is set-up to return an unknown token if it's nil.
        if @label
          e.modify! expected: @label
        end
        raise
      end
    end
  end

  # Turns parser into one that doesn't consume input.
  def peek(io)
    BackedIO.for(io) do |bio|
      begin
        parse bio
      ensure
        bio.restore
      end
    end
  end

  # <tt>x | y</tt> tries y if x fails.
  def |(p)
    Parsby.new "(#{self.label} or #{p.label})" do |io|
      begin
        parse io
      rescue Error
        p.parse io
      end
    end
  end

  # x < y runs parser x then y and returns x.
  def <(p)
    Parsby.new do |io|
      r = parse io
      p.parse io
      r
    end
  end

  # x > y runs parser x then y and returns y.
  def >(p)
    Parsby.new do |io|
      parse io
      p.parse io
    end
  end

  # p * n, runs parser p n times, grouping results in an array.
  def *(n)
    Parsby.new do |io|
      n.times.map { parse io }
    end
  end

  # x + y does + on the results of x and y. This is mostly meant to be used
  # with arrays, but it would work with numbers and strings too.
  def +(p)
    (Parsby.empty << self << p).fmap {|(x, y)| x + y }
  end

  # xs << x appends result of parser x to list result of parser xs.
  def <<(p)
    Parsby.new do |io|
      x = parse io
      y = p.parse io
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
    Parsby.new do |io|
      b.call parse io
    end
  end

  # Allows you to modify the exception to add information when defining the
  # parser via combinators.
  def on_catch(&b)
    Parsby.new do |io|
      begin
        parse io
      rescue ExpectationFailed => e
        b.call e
        raise
      end
    end
  end

  # Peeks to see whether parser would succeed if applied.
  def would_succeed(io)
    begin
      peek io
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
  #   Parsby::ExpectationFailed: expected (not "10"), actual 10, at 0
  def that_fails(p)
    Parsby.new do |bio|
      orig_pos = bio.pos
      begin
        r = p.parse bio
      rescue Error
        bio.restore
        parse bio
      else
        raise ExpectationFailed.new(
          expected: "(not #{p.label})",
          actual: "#{r}",
          at: orig_pos,
        )
      end
    end
  end

  alias_method :that_fail, :that_fails
end
