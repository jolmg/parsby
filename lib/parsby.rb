require "parsby/version"

class Parsby
  class Error < StandardError; end

  class Token
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def to_s
      "<#{name}>"
    end
  end

  class ExpectationFailed < Error
    attr_reader :opts

    def initialize(opts)
      @opts = opts
    end

    def message
      parts = []
      parts << "expected #{opts[:expected]}" if opts[:expected]
      parts << "actual #{opts[:actual]}" if opts[:actual]
      parts << "at #{opts[:at]}"
      parts.join(", ")
    end

    # I'd rather keep things immutable, but part of the original backtrace
    # is lost if we use a new one.
    def modify!(opts)
      self.opts.merge! opts
    end
  end

  class BackedIO
    attr_reader :backup

    def initialize(io, &b)
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

    def restore
      @backup.chars.reverse.each {|c| @io.ungetc c }
      @backup = ""
      nil
    end

    def eof?
      @io.eof?
    end

    def pos
      @io.pos
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
    @label || Token.new("unknown")
  end

  def label=(name)
    @label = name.is_a?(Symbol) ? Token.new(name) : name
  end

  def initialize(label = nil, &b)
    self.label = label if label
    @parser = b
  end

  # Parse a String or IO object.
  def parse(io)
    io = StringIO.new io if io.is_a? String
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

  # x | y tries y if x fails.
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

  # Set the label and return self.
  def %(name)
    self.label = name
    self
  end

  # Parses the string as literally provided.
  def self.string(e)
    new e.inspect do |io|
      a = io.read e.length
      if a == e
        a
      else
        # XXX: #parse of this instance will already recover from BackedIO's
        # backup. Isn't this causing restoration to be done twice?
        a.chars.reverse.each {|ac| io.ungetc ac } if a
        raise ExpectationFailed.new expected: e, actual: a, at: io.pos
      end
    end
  end

  # Uses =~ for matching. Only compares one char.
  def self.char_matching(r)
    new "char matching #{r.inspect}" do |io|
      pos = io.pos
      c = any_char.parse io
      unless c =~ r
        raise ExpectationFailed.new(
          actual: c,
          at: pos,
        )
      end
      c
    end
  end

  # Parses a decimal number as matched by \d+.
  def self.number
    many_1(char_matching(/\d/)) % "number"
  end

  # Runs parser until it fails and returns an array of the results. Because
  # it can return an empty array, this parser can never fail.
  def self.many(p)
    new do |io|
      rs = []
      while true
        break if io.eof?
        begin
          rs << p.parse(io)
        rescue Error
          break
        end
      end
      rs
    end
  end

  # Same as many, but fails if it can't match even once.
  def self.many_1(p)
    new do |io|
      r = p.parse io
      rs = many(p).parse io
      [r] + rs
    end
  end

  # Tries the given parser and returns nil if it fails.
  def self.optional(p)
    new do |io|
      begin
        p.parse io
      rescue Error
        nil
      end
    end
  end

  # Parses any char. Only fails on EOF.
  def self.any_char
    new do |io|
      if io.eof?
        raise ExpectationFailed.new(
          expected: :any_char,
          actual: :eof,
          at: io.pos,
        )
      end
      io.read 1
    end
  end

  # Like many, but accepts another parser for separators. It returns a list
  # of the results of the first argument. Returns an empty list if it
  # didn't match even once, so it never fails.
  def self.sep_by(p, s)
    new do |io|
      begin
        sep_by_1(p, s).parse io
      rescue Error
        []
      end
    end
  end

  # Like sep_by, but fails if it can't match even once.
  def self.sep_by_1(p, s)
    new do |io|
      r = p.parse io
      rs = many(s > p).parse io
      [r] + rs
    end
  end

  # Like map for arrays, this lets you work with the value "inside" the
  # parser, i.e. the result. decimal.fmap {|x| x + 1}.parse("2") == 3.
  def fmap(&b)
    Parsby.new do |io|
      b.call parse io
    end
  end

  # Matches EOF, fails otherwise. Returns nil.
  def self.eof
    Parsby.new :eof do |io|
      unless io.eof?
        raise ExpectationFailed.new(
          at: io.pos,
        )
      end
    end
  end

  # x.that_fail(y) will try y, fail if it succeeds, and parse x if it
  # fails.
  #
  # Example:
  #
  #   decimal.that_fail(string("10")).parse "3"
  #   => 3
  #   decimal.that_fail(string("10")).parse "10"
  #   => Exception
  def that_fail(p)
    Parsby.new do |bio|
      begin
        r = p.parse bio
      rescue Error
        bio.restore
        parse bio
      else
        raise ExpectationFailed.new(
          expected: "(not #{p.label})",
          actual: "#{r}",
          at: bio.pos,
        )
      end
    end
  end
end
