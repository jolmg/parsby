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
end
