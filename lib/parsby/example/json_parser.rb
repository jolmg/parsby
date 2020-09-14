require 'parsby'

module Parsby::Example
  module JsonParser
    include Parsby::Combinators
    extend self

    def parse(io)
      (spaced(value) < eof).parse io
    end

    define_combinator :value do
      null | bool | number | string | array | object
    end

    define_combinator :null do
      lit("null") > pure(nil)
    end

    define_combinator :bool do
      choice(
        lit("true") > pure(true),
        lit("false") > pure(false),
      )
    end

    # This has been adopted as Parsby::Combinators#fractional_decimal, but
    # we leave this definition here since this module is supposed to be an
    # example of using Parsby, and this works well for showing how to use
    # `group` and `fmap`.
    define_combinator :number  do
      sign = lit("-") | lit("+")
      group(
        optional(sign),
        decimal,
        optional(group(
          lit("."),
          decimal,
        )),
        optional(group(
          lit("e") | lit("E"),
          optional(sign),
          decimal,
        )),
      ).fmap do |(sign, whole, (_, fractional), (_, exponent_sign, exponent))|
        n = whole
        n += fractional.to_f / 10 ** fractional.to_s.length if fractional
        n *= -1 if sign == "-"
        if exponent
          e = exponent
          e *= -1 if exponent_sign == "-"
          n *= 10 ** e
        end
        n
      end
    end

    define_combinator :string do
      between(lit('"'), lit('"'),
        join(many(choice(
          any_char.that_fails(lit('"') | lit("\\")),
          lit("\\") > choice(
            lit('"'),
            lit("\\"),
            lit("/"),
            lit("f") > pure("\f"),
            lit("b") > pure("\b"),
            lit("r") > pure("\r"),
            lit("n") > pure("\n"),
            lit("t") > pure("\t"),
            lit("u") > join(hex_digit * 4).fmap {|s| [s.hex].pack("U") },
          ),
        )))
      )
    end

    define_combinator :array do
      between(lit("["), ws > lit("]"), sep_by(lit(","), spaced(lazy { value })))
    end

    define_combinator :object do
      between(lit("{"), ws > lit("}"),
        sep_by(lit(","),
          spaced(group(
            string < spaced(lit(":")),
            lazy { value }
          )),
        )
      ).fmap(&:to_h)
    end
  end
end
