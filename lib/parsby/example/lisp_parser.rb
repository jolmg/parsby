require "parsby"

module Parsby::Example
  module LispParser
    include Parsby::Combinators
    extend self

    def parse(io)
      sexp_sequence.parse io
    end

    def sexp_sequence
      many(whitespace > sexp) < whitespace < eof
    end

    def sexp
      abbrev | atom | list
    end

    # Add comments to definition of whitespace. whitespace is defined using
    # whitespace_1, so we cover both with this.
    def whitespace_1
      join(many_1(super | comment))
    end

    def comment
      string(";") \
        + join(many(any_char.that_fails(string("\n")))) \
        + (string("\n") | (eof > pure("")))
    end

    # Parses sexps with abbreviations, like '(foo bar) or `(foo ,bar).
    def abbrev
      choice(
        string("'") > lazy { sexp }.fmap {|s| [:quote, [s, nil]]},
        string("`") > lazy { sexp }.fmap {|s| [:quasiquote, [s, nil]]},
        string(",@") > lazy { sexp }.fmap {|s| [:"unquote-splicing", [s, nil]]},
        string(",") > lazy { sexp }.fmap {|s| [:unquote, [s, nil]]},
      )
    end

    def list
      Parsby.new :list do |io|
        braces = {"(" => ")", "[" => "]"}
        opening_brace = choice(braces.keys.map {|c| string c}).parse io
        (whitespace > inner_list < whitespace < string(braces[opening_brace])).parse io
      end
    end

    def inner_list
      (peek(string(")")) > pure(nil)) | (
        empty \
          << lazy { sexp } \
          << ((whitespace > string(".") > whitespace > lazy { sexp }) \
              | optional(whitespace > lazy { inner_list }))
      )
    end

    def atom
      number | lisp_string | symbol
    end

    def symbol
      join(many_1(choice_char(
        [
          *('a'..'z'),
          *('A'..'Z'),
          *('0'..'9'),
          # Got list from R6RS; removed '.' for simplicity.
          *%w(! $ % & * + - / : < = > ? @ ^ _ ~),
        ].flatten.join
      ))).fmap(&:to_sym)
    end

    def hex_digit
      choice(
        [("0".."9"), ("a".."f"), ("A".."F")]
          .map(&:to_a)
          .reduce(:+)
          .map {|c| string c }
      )
    end

    def escape_sequence
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

    def lisp_string
      Parsby::Token.new("string") % between(string('"'), string('"'),
        join(many(
          any_char.that_fails(string("\\") | string('"')) \
          | escape_sequence
        ))
      )
    end

    def number
      Parsby::Token.new("number") % (
        empty \
          << optional(string("-") | string("+")) \
          << decimal \
          << optional(empty << string(".") << optional(decimal))
      ).fmap do |(sign, whole_part, (_, fractional_part))|
        n = whole_part
        n += (fractional_part || 0).to_f / 10 ** fractional_part.to_s.length
        sign == "-" ? -n : n
      end
    end
  end
end
