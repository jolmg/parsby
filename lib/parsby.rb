require "parsby/version"

module Parsby
  class Error < StandardError; end
  # Your code goes here...

  class ExpectationFailed < Error
    attr_reader :expected, :actual, :at

    def initialize(expected:, actual:, at:)
      @expected = expected
      @actual = actual
      @at = at
      super "expected #{expected.inspect}, actual #{actual.inspect}, at #{at}"
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
  end

  def self.string(e)
    Combinator.new do |io|
      a = io.read e.length
      if a == e
        a
      else
        a.chars.each {|ac| io.ungetc ac }
        raise ExpectationFailed.new expected: e, actual: a, at: io.pos
      end
    end
  end
end
