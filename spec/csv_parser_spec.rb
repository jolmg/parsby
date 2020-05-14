RSpec.describe CsvParser do
  let :simple_csv do
    <<~EOF
      foo,bar
      1,2
      3,4
    EOF
  end

  it "parses simple csv files" do
    expect(CsvParser.parse <<~CSV)
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

  it "allows CRLF line terminators" do
    expect(CsvParser.parse <<~CSV)
      foo,bar\r
      1,2\r
      3,4\r
    CSV
      .to eq [
        ["foo", "bar"],
        ["1", "2"],
        ["3", "4"],
      ]
  end

  it "parses not so simple csv files" do
    expect(CsvParser.parse <<~CSV)
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

  it "does not accept invalid csv at the end (expects EOF)" do
    # If CsvParser didn't expect an EOF, this wouldn't raise an error. It
    # would just return what it could parse at the beginning.
    expect { CsvParser.parse <<~CSV }
      foo,bar
      1,2
      3,4
      invalid"invalid
    CSV
      .to raise_error Parsby::Error
  end
end
