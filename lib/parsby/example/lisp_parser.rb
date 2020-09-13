require "parsby"

module Parsby::Example
  module LispParser
    include Parsby::Combinators
    extend self

    def parse(io)
      sexp_sequence.parse io
    end

    define_combinator :sexp_sequence do
      many(spaced(sexp)) < eof
    end

    define_combinator :sexp, wrap_parser: false do
      lazy { choice(abbrev, atom, list) }
    end

    # Add comments to definition of whitespace. whitespace is defined using
    # whitespace_1, so we cover both with this.
    define_combinator :whitespace_1 do
      join(many_1(super() | comment))
    end

    define_combinator :comment do
      lit(";") \
        + join(many(any_char.that_fails(lit("\n")))) \
        + (lit("\n") | (eof > pure("")))
    end

    # Parses sexps with abbreviations, like '(foo bar) or `(foo ,bar).
    define_combinator :abbrev do
      ~splicer.start do
        choice(
          lit("'") > sexp.fmap {|s| [:quote, [s, nil]]},
          lit("`") > sexp.fmap {|s| [:quasiquote, [s, nil]]},
          lit(",@") > sexp.fmap {|s| [:"unquote-splicing", [s, nil]]},
          lit(",") > sexp.fmap {|s| [:unquote, [s, nil]]},
        )
      end
    end

    define_combinator :list do
      braces = {"(" => ")", "[" => "]"}

      ~splicer.start do |m|
        m.end(char_in(braces.keys.join)).then do |opening_brace|
          spaced(list_insides(m)) < m.end(lit(braces[opening_brace]))
        end
      end
    end

    define_combinator :list_insides do |m|
      optional(
        group(
          m.end(sexp),
          choice(
            spaced(m.end(lit("."))) > m.end(sexp),
            whitespace > lazy { list_insides(m) },
          ),
        )
      )
    end

    define_combinator :atom do
      ~choice(number, string, self.nil, symbol)
    end

    define_combinator :nil do
      ilit("nil") > pure(nil)
    end

    define_combinator :symbol_char do
      char_in(
        [
          *('a'..'z'),
          *('A'..'Z'),
          *('0'..'9'),
          # Got list from R6RS; removed '.' for simplicity.
          *%w(! $ % & * + - / : < = > ? @ ^ _ ~),
        ].flatten.join
      )
    end

    define_combinator :symbol do
      ~splicer.start { join(many_1(symbol_char)).fmap(&:to_sym) }
    end

    define_combinator :hex_digit do
      char_in(
        [*("0".."9"), *("a".."f"), *("A".."F")]
          .flatten
          .join
      )
    end

    define_combinator :escape_sequence do
      lit("\\") > choice([
        lit("\"") > pure("\""),
        lit("n") > pure("\n"),
        lit("t") > pure("\t"),
        lit("r") > pure("\r"),
        lit("x") > (hex_digit * 2)
          .fmap {|(d1, d2)| (d1 + d2).to_i(16).chr },
        lit("\\"),
      ])
    end

    define_combinator :string do
      ~splicer.start do
        between(lit('"'), lit('"'),
          join(many(choice(
            any_char.that_fails(lit("\\") | lit('"')),
            escape_sequence,
          )))
        )
      end
    end

    define_combinator :number do
      ~splicer.start do
        group(
          optional(lit("-") | lit("+")),
          decimal,
          optional(empty << lit(".") << optional(decimal)),
        ).fmap do |(sign, whole_part, (_, fractional_part))|
          n = whole_part
          n += (fractional_part || 0).to_f / 10 ** fractional_part.to_s.length
          sign == "-" ? -n : n
        end
      end
    end
  end
end
