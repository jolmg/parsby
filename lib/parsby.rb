require "parsby/version"

class Parsby
  class Error < StandardError; end

  class ExpectationFailed < Error
    attr_reader :opts

    def initialize(opts)
      @opts = opts
      super [
        "expected #{opts[:label] || opts[:expected].inspect}",
        "actual #{opts[:actual].inspect}",
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
      end
    end

    def restore
      @backup.chars.reverse.each {|c| @io.ungetc c }
      @backup = ""
      nil
    end

    def read(count)
      @io.read(count).tap {|r| @backup << r }
    end
  end

  def initialize(&b)
    @parser = b
  end

  def parse(io)
    io = StringIO.new io if io.is_a? String
    @parser.call io
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

  def %(label)
    Parsby.new do |io|
      begin
        parse io
      rescue ExpectationFailed => e
        e = e.modifying label: label
        raise e
      end
    end
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

  def self.sepBy(p, s)
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

  def failing(p)
    Parsby.new do |io|
      io.start_backup
      begin
        p.parse io
      rescue Error
        parse io
      else
        io.restore
        raise Error
      ensure
        io.stop_backup
      end
    end
  end
end
