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
      expected = opts[:expected]
      actual = opts[:actual]
      parts = []
      parts << "expected #{expected}" if expected
      parts << "actual #{actual}" if actual
      parts << "at #{opts[:at]}"
      super parts.join(", ")
    end

    def modifying(opts)
      self.class.new self.opts.merge opts
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

  def parse(io)
    io = StringIO.new io if io.is_a? String
    BackedIO.for io do |bio|
      begin
        @parser.call bio
      rescue ExpectationFailed => e
        # Use the instance variable instead of the reader since the reader
        # is set-up to return an unknown token if it's nil.
        if @label
          e = e.modifying expected: @label
        end
        raise e
      end
    end
  end

  def |(p)
    Parsby.new "(#{self.label} or #{p.label})" do |io|
      begin
        parse io
      rescue Error
        p.parse io
      end
    end
  end

  def <(p)
    Parsby.new do |io|
      r = parse io
      p.parse io
      r
    end
  end

  def >(p)
    Parsby.new do |io|
      parse io
      p.parse io
    end
  end

  def %(name)
    self.label = name
    self
  end

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

  def self.number
    many_1(char_matching(/\d/)) % "number"
  end

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

  def self.many_1(p)
    new do |io|
      r = p.parse io
      rs = many(p).parse io
      [r] + rs
    end
  end

  def self.optional(p)
    new do |io|
      begin
        p.parse io
      rescue Error
        nil
      end
    end
  end

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

  def self.sep_by(p, s)
    new do |io|
      begin
        sep_by_1(p, s)
      rescue Error
        []
      end
    end
  end

  def self.sep_by_1(p, s)
    new do |io|
      r = p.parse io
      rs = many(s > p).parse io
      [r] + rs
    end
  end

  def fmap(&b)
    Parsby.new do |io|
      b.call parse io
    end
  end

  def self.eof
    Parsby.new :eof do |io|
      unless io.eof?
        raise ExpectationFailed.new(
          at: io.pos,
        )
      end
    end
  end

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
