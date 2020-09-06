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

    define_combinator :list, wrap_parser: false do
      Parsby.new :list do |io|
        braces = {"(" => ")", "[" => "]"}
        opening_brace = char_in(braces.keys.join).parse io
        (spaced(list_insides) < lit(braces[opening_brace])).parse io
      end
    end

    define_combinator :list_insides do
      choice(
        peek(lit(")")) > pure(nil),
        group(
          lazy { sexp },
          choice(
            spaced(lit(".")) > lazy { sexp },
            optional(whitespace > lazy { list_insides }),
          ),
        ),
      )
    end

    define_combinator :atom do
      number | lisp_string | symbol
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

    define_combinator :symbol, splicing: [] do
      join(many_1(symbol_char)).fmap(&:to_sym)
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

    define_combinator :lisp_string, splicing: [] do
      between(lit('"'), lit('"'),
        join(many(choice(
          any_char.that_fails(lit("\\") | lit('"')),
          escape_sequence,
        )))
      )
    end

    define_combinator :number, splicing: [] do
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
