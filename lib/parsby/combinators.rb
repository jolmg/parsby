class Parsby
  module Combinators
    extend self

    def self.define_combinator(name, &b)
      # Trick to enforce arity of procs by converting them to methods.
      m = Module.new.module_exec do
        define_method(:_, &b)
        instance_method(:_)
      end

      inspect_arg = lambda do |arg|
        case arg
        when Parsby
          arg.label
        when Array
          arg.map(&inspect_arg)
        when Hash
          arg.map {|k, v| [k, inspect_arg.call(v)] }.to_h
        else
          arg.inspect
        end
      end

      define_method name do |*args, &b2|
        m.bind(self).call(*args, &b2) % "#{name}(#{args.map(&inspect_arg).join(", ")})"
      end
    end

    # Parses the string as literally provided.
    define_combinator :string do |e|
      Parsby.new e.inspect do |io|
        a = io.read e.length
        if a == e
          a
        else
          raise ExpectationFailed.new io
        end
      end
    end

    # Same as <tt>p * n</tt>
    define_combinator :count do |n, p|
      p * n % "count(#{n}, #{p.label})"
    end

    # Uses =~ for matching. Only compares one char.
    define_combinator :char_matching do |r|
      Parsby.new r.inspect do |io|
        pos = io.pos
        c = any_char.parse io
        unless c =~ r
          raise ExpectationFailed.new io
        end
        c
      end
    end

    # Parses a decimal number as matched by \d+.
    define_combinator :decimal do
      many_1(decimal_digit).fmap {|ds| ds.join.to_i } % token("number")
    end

    # Parses single digit in range 0-9. Returns string, not number.
    define_combinator :decimal_digit do
      char_matching /[0-9]/
    end

    # Parses single hex digit. Optional argument lettercase can be one of
    # :insensitive, :upper, or :lower.
    define_combinator :hex_digit do |lettercase = :insensitive|
      decimal_digit | case lettercase
      when :insensitive
        char_matching /[a-fA-F]/
      when :upper
        char_matching /[A-F]/
      when :lower
        char_matching /[a-f]/
      else
        raise ArgumentError.new(
          "#{lettercase.inspect}: unrecognized; argument should be one of " \
          ":insensitive, :upper, or :lower"
        )
      end
    end

    # Parser that always fails without consuming input. We use it for at
    # least <tt>choice</tt>, for when it's supplied an empty list. It
    # corresponds with mzero in Haskell's Parsec.
    define_combinator :unparseable do
      Parsby.new {|io| raise ExpectationFailed.new io }
    end

    # Tries each provided parser until one succeeds. Providing an empty
    # list causes parser to always fail, like how [].any? is false.
    define_combinator :choice do |*ps|
      ps = ps.flatten
      ps.reduce(unparseable, :|) % "(one of #{ps.map(&:label).join(", ")})"
    end

    define_combinator :choice_char do |s|
      choice s.chars.map {|c| string c }
    end

    # Parses string of 0 or more continuous whitespace characters (" ",
    # "\t", "\n", "\r")
    define_combinator :whitespace do
      token("whitespace") % (whitespace_1 | pure(""))
    end

    alias_method :ws, :whitespace

    # Parses string of 1 or more continuous whitespace characters (" ",
    # "\t", "\n", "\r")
    define_combinator :whitespace_1 do
      token("whitespace_1") % join(many_1(choice(*" \t\n\r".chars.map(&method(:string)))))
    end

    alias_method :ws_1, :whitespace_1

    # Expects p to be surrounded by optional whitespace.
    define_combinator :spaced do |p|
      ws > p < ws
    end

    # Convinient substitute of <tt>left > p < right</tt> for when
    # <tt>p</tt> is large to write.
    define_combinator :between do |left, right, p|
      left > p < right
    end

    # Turns parser into one that doesn't consume input.
    define_combinator :peek do |p|
      Parsby.new {|io| p.peek io }
    end

    # Parser that returns provided value without consuming any input.
    define_combinator :pure do |x|
      Parsby.new { x }
    end

    # Delays construction of parser until parsing-time. This allows one to
    # construct recursive parsers, which would otherwise result in a
    # stack-overflow in construction-time.
    define_combinator :lazy do |&b|
      # Can't have a better label, because we can't know what the parser is
      # until parsing time.
      Parsby.new {|io| b.call.parse io }
    end

    # Results in empty array without consuming input. This is meant to be
    # used to start off use of <<.
    #
    # Example:
    #
    #   (empty << string("foo") << string("bar")).parse "foobar"
    #   => ["foo", "bar"]
    define_combinator :empty do
      pure []
    end

    # Groups results into an array.
    define_combinator :group do |*ps|
      ps = ps.flatten
      ps.reduce(empty, :<<)
    end

    # Wraps result in a list. This is to be able to do
    #
    #   single(...) + many(...)
    define_combinator :single do |p|
      p.fmap {|x| [x]}
    end

    # Runs parser until it fails and returns an array of the results. Because
    # it can return an empty array, this parser can never fail.
    define_combinator :many do |p|
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
    define_combinator :many_1 do |p|
      single(p) + many(p)
    end

    # Like many, but accepts another parser for separators. It returns a list
    # of the results of the first argument. Returns an empty list if it
    # didn't match even once, so it never fails.
    define_combinator :sep_by do |p, s|
      sep_by_1(p, s) | empty
    end

    # Like sep_by, but fails if it can't match even once.
    define_combinator :sep_by_1 do |p, s|
      single(p) + many(s > p)
    end

    # Join the Array result of p.
    define_combinator :join do |p|
      p.fmap(&:join)
    end

    # Tries the given parser and returns nil if it fails.
    define_combinator :optional do |p|
      Parsby.new do |io|
        begin
          p.parse io
        rescue Error
          nil
        end
      end
    end

    # Parses any char. Only fails on EOF.
    define_combinator :any_char do
      Parsby.new do |io|
        if io.eof?
          raise ExpectationFailed.new io
        end
        io.read 1
      end
    end

    # The same as Parsby.new, just shorter and without capitals.
    def parsby(*args, &b)
      Parsby.new(*args, &b)
    end

    # Matches EOF, fails otherwise. Returns nil.
    define_combinator :eof do
      Parsby.new :eof do |io|
        unless io.eof?
          raise ExpectationFailed.new io
        end
      end
    end

    # Take characters until p matches.
    define_combinator :take_until do |p, with: any_char|
      Parsby.new do |io|
        r = ""
        until p.would_succeed(io)
          r << with.parse(io)
        end
        r
      end
    end

    # Makes a token with the given name.
    def token(name)
      Parsby::Token.new name
    end
  end
end
