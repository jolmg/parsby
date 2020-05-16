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
      super [
        "expected #{expected.nil? ? "nil" : expected}",
        "actual #{actual.nil? ? "nil" : actual}",
        "at #{opts[:at]}",
      ].join(", ")
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

  attr_reader :label

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
        if @label
          e = e.modifying expected: @label.to_sym
        end
        raise e
      end
    end
  end

  def |(p)
    Parsby.new do |io|
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
  end

  def self.string(e)
    new do |io|
      a = io.read e.length
      if a == e
        a
      else
        a.chars.reverse.each {|ac| io.ungetc ac } if a
        raise ExpectationFailed.new expected: e, actual: a, at: io.pos
      end
    end
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
        r = p.parse io
      rescue Error
        []
      else
        rs = many(s > p).parse io
        [r] + rs
      end
    end
  end

  def fmap(&b)
    Parsby.new do |io|
      b.call parse io
    end
  end

  def self.eof
    Parsby.new do |io|
      raise Error unless io.eof?
    end
  end

  def that_fail(p)
    Parsby.new do |bio|
      begin
        p.parse bio
      rescue Error
        bio.restore
        parse bio
      else
        # XXX: Would be nice if this were more informative. Unfortunately
        # for that, we need to make p's label accessible despite not having
        # thrown an error.
        raise Error
      end
    end
  end
end
