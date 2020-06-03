require 'parsby'

# This is based on:
# 
# RFC 4180: Common Format and MIME Type for Comma-Separated Values (CSV) Files
module Parsby::Example
  module CsvParser
    include Parsby::Combinators
    extend self

    def parse(source)
      csv.parse source
    end

    def csv
      many(record) < eof
    end

    def record
      sep_by(cell, string(",")) < (eol | eof)
    end

    def cell
      quoted_cell | non_quoted_cell
    end

    def quoted_cell
      non_quote = many(any_char.that_fail(string('"'))).fmap(&:join)
      inner = sep_by(non_quote, string('""')).fmap {|r| r.join '"' }
      string('"') > inner < string('"')
    end

    def non_quoted_cell
      many(any_char.that_fail(string(",") | string("\"") | eol)).fmap(&:join)
    end

    def eol
      string("\r\n") | string("\n")
    end
  end
end
