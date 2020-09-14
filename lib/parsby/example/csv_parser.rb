require 'parsby'

# This is based on:
# 
# RFC 4180: Common Format and MIME Type for Comma-Separated Values (CSV) Files
module Parsby::Example
  module CsvParser
    include Parsby::Combinators
    extend self

    def parse(io)
      csv.parse io
    end

    define_combinator :csv do
      many(record) < eof
    end

    define_combinator :record do
      sep_by(lit(","), cell) < (eol | eof)
    end

    define_combinator :cell do
      quoted_cell | non_quoted_cell
    end

    define_combinator :quoted_cell do
      non_quote = join(many(any_char.that_fail(lit('"'))))
      inner = sep_by(lit('""'), non_quote).fmap {|r| r.join '"' }
      lit('"') > inner < lit('"')
    end

    define_combinator :non_quoted_cell do
      join(many(any_char.that_fail(lit(",") | lit("\"") | eol)))
    end

    define_combinator :eol do
      lit("\r\n") | lit("\n")
    end
  end
end
