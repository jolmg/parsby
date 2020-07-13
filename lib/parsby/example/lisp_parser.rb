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
      abbrev | atom | list
    end

    # Add comments to definition of whitespace. whitespace is defined using
    # whitespace_1, so we cover both with this.
    define_combinator :whitespace_1 do
      join(many_1(super() | comment))
    end

    define_combinator :comment do
      string(";") \
        + join(many(any_char.that_fails(string("\n")))) \
        + (string("\n") | (eof > pure("")))
    end

    # Parses sexps with abbreviations, like '(foo bar) or `(foo ,bar).
    define_combinator :abbrev do
      choice(
        string("'") > lazy { sexp }.fmap {|s| [:quote, [s, nil]]},
        string("`") > lazy { sexp }.fmap {|s| [:quasiquote, [s, nil]]},
        string(",@") > lazy { sexp }.fmap {|s| [:"unquote-splicing", [s, nil]]},
        string(",") > lazy { sexp }.fmap {|s| [:unquote, [s, nil]]},
      )
    end

    define_combinator :list, wrap_parser: false do
      Parsby.new :list do |io|
        braces = {"(" => ")", "[" => "]"}
        opening_brace = char_in(braces.keys.join).parse io
        (spaced(inner_list) < string(braces[opening_brace])).parse io
      end
    end

    define_combinator :inner_list do
      choice(
        peek(string(")")) > pure(nil),
        group(
          lazy { sexp },
          choice(
            spaced(string(".")) > lazy { sexp },
            optional(whitespace > lazy { inner_list }),
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

    define_combinator :symbol do
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
      string("\\") > choice([
        string("\"") > pure("\""),
        string("n") > pure("\n"),
        string("t") > pure("\t"),
        string("r") > pure("\r"),
        string("x") > (hex_digit * 2)
          .fmap {|(d1, d2)| (d1 + d2).to_i(16).chr },
        string("\\"),
      ])
    end

    define_combinator :lisp_string do
      Parsby.wrap :string, primitive: true do
        between(string('"'), string('"'),
          join(many(choice(
            any_char.that_fails(string("\\") | string('"')),
            escape_sequence,
          )))
        )
      end
    end

    define_combinator :number do
      group(
        optional(string("-") | string("+")),
        decimal,
        optional(empty << string(".") << optional(decimal)),
      ).fmap do |(sign, whole_part, (_, fractional_part))|
        n = whole_part
        n += (fractional_part || 0).to_f / 10 ** fractional_part.to_s.length
        sign == "-" ? -n : n
      end
    end
  end
end
