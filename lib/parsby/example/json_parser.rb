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
      string("null") > pure(nil)
    end

    def bool
      choice(
        string("true") > pure(true),
        string("false") > pure(false),
      )
    end

    # This has been adopted as Parsby::Combinators#fractional_decimal, but
    # we leave this definition here since this module is supposed to be an
    # example of using Parsby, and this works well for showing how to use
    # `group` and `fmap`.
    def number 
      sign = string("-") | string("+")
      group(
        optional(sign),
        decimal,
        optional(group(
          string("."),
          decimal,
        )),
        optional(group(
          string("e") | string("E"),
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

    def json_string
      between(string('"'), string('"'),
        join(many(choice(
          any_char.that_fails(string('"') | string("\\")),
          string("\\") > choice(
            string('"'),
            string("\\"),
            string("/"),
            string("f") > pure("\f"),
            string("b") > pure("\b"),
            string("r") > pure("\r"),
            string("n") > pure("\n"),
            string("t") > pure("\t"),
            string("u") > join(hex_digit * 4).fmap {|s| [s.hex].pack("U") },
          ),
        )))
      )
    end

    def array
      between(string("["), ws > string("]"), sep_by(spaced(lazy { value }), string(",")))
    end

    def object
      between(string("{"), ws > string("}"),
        sep_by(
          spaced(group(
            json_string < spaced(string(":")),
            lazy { value }
          )),
          string(","),
        )
      ).fmap(&:to_h)
    end
  end
end
