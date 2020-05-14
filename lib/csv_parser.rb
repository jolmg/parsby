class CsvParser < Parsby
  def self.parse(source)
    csv.parse source
  end

  def self.csv
    many(record) < eof
  end

  def self.record
    sepBy(cell, string(",")) < string("\n")
  end

  def self.cell
    quoted_cell | non_quoted_cell
  end

  def self.quoted_cell
    non_quote = many(anyChar.failing(string('"'))).fmap(&:join)
    inner = sepBy(non_quote, string('""'))
    (string('"') > inner < string('"')).fmap do |r|
      r.join('"')
    end
  end

  def self.non_quoted_cell
    many(anyChar.failing(string(",") | string("\"") | string("\n"))).fmap(&:join)
  end
end
