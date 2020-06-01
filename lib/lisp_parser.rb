require "parsby"

module LispParser
  include Parsby::Combinators
  extend self

  def sexp
    whitespace > (atom | list)
  end

  def whitespace
    # allow comments
    many_join(whitespace_1 | string(";") + many_join(any_char.that_fails(string("\n"))))
  end

  def list
    between(string("(") > whitespace, whitespace < string(")"),
      sep_by(sexp, whitespace)
    )
  end

  def atom
    number | lisp_string | symbol
  end

  def symbol
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
    between(string('"'), string('"'),
      many(
        any_char.that_fails(string("\\") | string('"')) \
        | escape_sequence
      ).fmap(&:join)
    )
  end

  def number
    (
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
