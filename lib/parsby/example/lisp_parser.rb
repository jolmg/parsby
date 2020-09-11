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

    define_combinator :sexp do
      choice(abbrev, atom, list)
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
      choice(
        lit("'") > lazy { sexp }.fmap {|s| [:quote, [s, nil]]},
        lit("`") > lazy { sexp }.fmap {|s| [:quasiquote, [s, nil]]},
        lit(",@") > lazy { sexp }.fmap {|s| [:"unquote-splicing", [s, nil]]},
        lit(",") > lazy { sexp }.fmap {|s| [:unquote, [s, nil]]},
      )
    end

    define_combinator :list do
      ~splicer.start do |m|
        Parsby.new :list do |io|
          braces = {"(" => ")", "[" => "]"}
          opening_brace = char_in(braces.keys.join).parse io
          (m.end(spaced(list_insides)) < lit(braces[opening_brace])).parse io
        end
      end
    end

    define_combinator :list_insides do
      ~splicer.start do |m|
        choice(
          peek(lit(")")) > pure(nil),
          group(
            lazy { m.end sexp },
            choice(
              m.end(spaced(lit(".")) > lazy { sexp }),
              optional(whitespace > lazy { m.end list_insides }),
            ),
          ),
        )
      end
    end

    define_combinator :atom do
      ~choice(number, string, symbol)
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
