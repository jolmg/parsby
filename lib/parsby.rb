require "parsby/version"

module Parsby
  class Error < StandardError; end
  # Your code goes here...

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
        raise Error
      end
    end
  end
end
