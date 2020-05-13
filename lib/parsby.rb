require "parsby/version"

module Parsby
  class Error < StandardError; end
  # Your code goes here...

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

  class Combinator
    def initialize(&b)
      @parser = b
    end

    def parse(io)
      io = StringIO.new io if io.is_a? String
      @parser.call io
    end

    def |(p)
      Combinator.new do |io|
        begin
          parse io
        rescue Error
          p.parse io
        end
      end
    end

    def <(p)
      Combinator.new do |io|
        r = parse io
        p.parse io
        r
      end
    end

    def >(p)
      Combinator.new do |io|
        parse io
        p.parse io
      end
    end

    def %(label)
      Combinator.new do |io|
        begin
          parse io
        rescue ExpectationFailed => e
          e = e.modifying label: label
          raise e
        end
      end
    end
  end

  def self.string(e)
    Combinator.new do |io|
      a = io.read e.length
      if a == e
        a
      else
        a.chars.reverse.each {|ac| io.ungetc ac }
        raise ExpectationFailed.new expected: e, actual: a, at: io.pos
      end
    end
  end
end
