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
end
