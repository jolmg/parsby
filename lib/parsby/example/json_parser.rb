require 'parsby'

module Parsby::Example
  module JsonParser
    include Parsby::Combinators
    extend self

    def parse(io)
      (spaced(value) < eof).parse io
    end

    def value
      null | bool | number | json_string | array | object
    end

    def null
      lit("null") > pure(nil)
    end

    def bool
      choice(
        lit("true") > pure(true),
        lit("false") > pure(false),
      )
    end

    # This has been adopted as Parsby::Combinators#fractional_decimal, but
    # we leave this definition here since this module is supposed to be an
    # example of using Parsby, and this works well for showing how to use
    # `group` and `fmap`.
    def number 
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

    def string
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

    def array
      between(lit("["), ws > lit("]"), sep_by(spaced(lazy { value }), lit(",")))
    end

    def object
      between(lit("{"), ws > lit("}"),
        sep_by(
          spaced(group(
            json_string < spaced(lit(":")),
            lazy { value }
          )),
          lit(","),
        )
      ).fmap(&:to_h)
    end
  end
end
