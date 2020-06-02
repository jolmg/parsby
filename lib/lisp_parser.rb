require "parsby"

module LispParser
  include Parsby::Combinators
  extend self

  def sexp_sequence
    many(whitespace > sexp) < whitespace < eof
  end

  def sexp
    abbrev | atom | list
  end

  # Add comments to definition of whitespace. whitespace is defined using
  # whitespace_1, so we cover both with this.
  def whitespace_1
    many_1(super | string(";") + many_join(any_char.that_fails(string("\n")))).fmap(&:join)
  end

  def abbrev
    choice(
      string("'") > lazy { sexp }.fmap {|s| [:quote, [s, nil]]},
      string("`") > lazy { sexp }.fmap {|s| [:quasiquote, [s, nil]]},
      string(",@") > lazy { sexp }.fmap {|s| [:"unquote-splicing", [s, nil]]},
      string(",") > lazy { sexp }.fmap {|s| [:unquote, [s, nil]]},
    )
  end

  def list
    Parsby::Token.new("list") % (
      string("(") > whitespace > inner_list < whitespace < string(")")
    )
  end

  def inner_list
    (
      collect \
        & lazy { sexp } \
        & ((whitespace > string(".") > whitespace > lazy { sexp }) \
            | optional(whitespace > lazy { inner_list }))
    ) | pure(nil)
  end

  def atom
    number | lisp_string | symbol
  end

  def symbol
    many_1_join(choice(
      [
        *('a'..'z'),
        *('A'..'Z'),
        *('0'..'9'),
        # Got list from R6RS
        *%w(! $ % & * + - . / : < = > ? @ ^ _ ~),
      ].map {|c| string c}
    )).fmap(&:to_sym)
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
      string("n") > pure("\n"),
      string("t") > pure("\t"),
      string("r") > pure("\r"),
      string("x") > (hex_digit & hex_digit)
        .fmap {|(d1, d2)| (d1 + d2).to_i(16).chr },
      string("\\"),
    ])
  end

  def lisp_string
    Parsby::Token.new("string") % between(string('"'), string('"'),
      many(
        any_char.that_fails(string("\\") | string('"')) \
        | escape_sequence
      ).fmap(&:join)
    )
  end

  def number
    Parsby::Token.new("number") % (
      collect \
        & optional(string("-") | string("+")) \
        & decimal \
        & optional(string(".") & optional(decimal))
    ).fmap do |(sign, whole_part, (_, fractional_part))|
      n = whole_part
      n += (fractional_part || 0).to_f / 10 ** fractional_part.to_s.length
      sign == "-" ? -n : n
    end
  end
end
