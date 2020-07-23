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

    def csv
      many(record) < eof
    end

    def record
      sep_by(cell, lit(",")) < (eol | eof)
    end

    def cell
      quoted_cell | non_quoted_cell
    end

    def quoted_cell
      non_quote = join(many(any_char.that_fail(lit('"'))))
      inner = sep_by(non_quote, lit('""')).fmap {|r| r.join '"' }
      lit('"') > inner < lit('"')
    end

    def non_quoted_cell
      join(many(any_char.that_fail(lit(",") | lit("\"") | eol)))
    end

    def eol
      lit("\r\n") | lit("\n")
    end
  end
end
