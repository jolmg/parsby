class Parsby
  module Combinators
    extend self

    # Parses the string as literally provided.
    def string(e)
      Parsby.new e.inspect do |io|
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
    def char_matching(r)
      Parsby.new "char matching #{r.inspect}" do |io|
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
    def decimal
      many_1(char_matching(/\d/)).fmap {|ds| ds.join.to_i } % "number"
    end

    # Runs parser until it fails and returns an array of the results. Because
    # it can return an empty array, this parser can never fail.
    def many(p)
      Parsby.new do |io|
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
    def many_1(p)
      Parsby.new do |io|
        r = p.parse io
        rs = many(p).parse io
        [r] + rs
      end
    end

    # Tries the given parser and returns nil if it fails.
    def optional(p)
      Parsby.new do |io|
        begin
          p.parse io
        rescue Error
          nil
        end
      end
    end

    # Parses any char. Only fails on EOF.
    def any_char
      Parsby.new do |io|
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
    def sep_by(p, s)
      Parsby.new do |io|
        begin
          sep_by_1(p, s).parse io
        rescue Error
          []
        end
      end
    end

    # Like sep_by, but fails if it can't match even once.
    def sep_by_1(p, s)
      Parsby.new do |io|
        r = p.parse io
        rs = many(s > p).parse io
        [r] + rs
      end
    end

    # Matches EOF, fails otherwise. Returns nil.
    def eof
      Parsby.new :eof do |io|
        unless io.eof?
          raise ExpectationFailed.new(
            at: io.pos,
          )
        end
      end
    end
  end
end
