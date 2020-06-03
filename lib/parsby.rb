require "parsby/version"
require "parsby/combinators"

class Parsby
  extend Combinators

  class Error < StandardError; end

  class ExpectationFailed < Error
    attr_reader :opts

    def initialize(opts)
      @opts = opts
    end

    def message
      parts = []
      parts << "expected #{opts[:expected]}" if opts[:expected]
      parts << "actual #{opts[:actual].inspect}" if opts[:actual]
      parts << "at #{opts[:at]}"
      parts.join(", ")
    end

    # I'd rather keep things immutable, but part of the original backtrace
    # is lost if we use a new one.
    def modify!(opts)
      self.opts.merge! opts
    end
  end

  class Token
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def to_s
      "<#{name}>"
    end

    # Compare tokens
    def ==(t)
      t.is_a?(self.class) && t.name == name
    end

    def %(p)
      p % self
    end
  end

  class BackedIO
    def initialize(io)
      io = StringIO.new io if io.is_a? String
      @io = io
      @backup = ""
    end

    def self.for(io, &b)
      bio = new io
      begin
        b.call bio
      rescue
        bio.restore
        raise
      end
    end

    def restore(n = @backup.length)
      n.times { ungetc @backup[-1] }
      nil
    end

    def method_missing(m, *args, &b)
      @io.send(m, *args, &b)
    end

    def read(count)
      @io.read(count).tap {|r| @backup << r unless r.nil? }
    end

    def ungetc(c)
      @backup.slice! @backup.length - c.length
      @io.ungetc(c)
    end
  end

  def label
    @label ||= Token.new("unknown")
  end

  def label=(name)
    @label = name.is_a?(Symbol) ? Token.new(name) : name
  end

  def initialize(label = nil, ignore: false, &b)
    self.label = label if label
    @ignore = ignore
    @parser = b
  end

  def ignore?
    @ignore ||= false
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

  # Like &, but joins results with + and isn't affected by ignore flag.
  def +(p)
    (Parsby.collect & self & p).fmap {|(x, y)| x + y }
  end

  # Returns a parser that's to be ignored by &.
  def -@
    self.class.new(ignore: true) {|io| parse io }
  end

  # Groups results in an array.
  def &(p)
    Parsby.new do |io|
      x = parse io
      y = p.parse io
      r = x.is_a?(Array) ? x : ignore? ? [] : [x]
      r += [y] unless p.ignore?
      r
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
