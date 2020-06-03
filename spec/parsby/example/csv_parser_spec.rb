RSpec.describe Parsby::Example::CsvParser do
  let :simple_csv do
    <<~EOF
      foo,bar
      1,2
      3,4
    EOF
  end

  it "parses simple csv files" do
    expect(Parsby::Example::CsvParser.parse <<~CSV)
      foo,bar
      1,2
      3,4
    CSV
      .to eq [
        ["foo", "bar"],
        ["1", "2"],
        ["3", "4"],
      ]
  end

  it "parses not so simple csv files" do
    expect(Parsby::Example::CsvParser.parse <<~CSV)
      "
      foo","bar
      "
      "1,1","2
      2"
      "3
      3","4""4"
    CSV
      .to eq [
        ["\nfoo", "bar\n"],
        ["1,1", "2\n2"],
        ["3\n3", "4\"4"],
      ]
  end

  it "allows CRLF line terminators" do
    expect(Parsby::Example::CsvParser.parse <<~CSV)
      foo,bar\r
      1,2\r
    CSV
      .to eq [
        ["foo", "bar"],
        ["1", "2"],
      ]
  end

  it "allows last line to not have line terminator" do
    expect(Parsby::Example::CsvParser.parse <<~CSV.chomp)
      foo,bar
      1,2
    CSV
      .to eq [
        ["foo", "bar"],
        ["1", "2"],
      ]

    expect(Parsby::Example::CsvParser.parse <<~CSV.chomp)
      foo,bar\r
      1,2\r
    CSV
      .to eq [
        ["foo", "bar"],
        ["1", "2"],
      ]
  end

  it "accepts an empty CSV" do
    expect(Parsby::Example::CsvParser.parse "").to eq []
  end

  it "correctly interprets an empty line" do
    expect(Parsby::Example::CsvParser.parse "\n").to eq [[""]]
  end

  it "does not accept invalid csv at the end (expects EOF)" do
    # If Parsby::Example::CsvParser didn't expect an EOF, this wouldn't raise an error. It
    # would just return what it could parse at the beginning.
    expect { Parsby::Example::CsvParser.parse <<~CSV }
      foo,bar
      1,2
      invalid"invalid
    CSV
      .to raise_error Parsby::Error
  end

  describe "#cell" do
    it "parses quoted or unquoted cells"
  end

  describe "#csv" do
    it "parses a csv whole"
    it "expects eof"
  end

  describe "#eol" do
    it "allows either LF or CRLF line terminators"
  end

  describe "#parse" do
    it "entrypoint that delegates to #csv"
  end

  describe "#record" do
    it "parses a single record"
    it "fails on invalid syntax"
  end

  describe "#quoted_cell" do
    it "can contain field separators inside"
    it "can span multiple lines"
    it "releases escaped double-quotes"
  end

  describe "#non_quoted_cell" do
    it "stops on field separator or double-quotes"
  end
end
