RSpec.describe Parsby::Example::JsonParser do
  include Parsby::Example::JsonParser

  describe "#parse" do
    it "allows spaces around value" do
      expect(parse(" null ")).to eq nil
    end

    it "reads whole content for single value (expects eof)" do
      expect { parse(" null foo") }.to raise_error Parsby::ExpectationFailed
    end
  end

  describe "#value" do
    it "parses all possible json values" do
      expect(value.parse "true").to eq true
      expect(value.parse "null").to eq nil
      expect(value.parse "5").to eq 5
      expect(value.parse '"foo"').to eq "foo"
      expect(value.parse '[]').to eq []
      expect(value.parse '{}').to eq({})
    end
  end

  describe "#bool" do
    it "parses true or false" do
      expect(bool.parse "true").to eq true
      expect(bool.parse "false").to eq false
    end
  end

  describe "#null" do
    it "parses null" do
      expect(null.parse "null").to eq nil
    end
  end

  describe "#json_string" do
    it "parses simple strings" do
      expect(json_string.parse '"foo"').to eq "foo"
    end

    it "accepts escape sequences" do
      expect(json_string.parse '"fo\\"o"').to eq "fo\"o"
      expect(json_string.parse '"fo\\no"').to eq "fo\no"
      expect(json_string.parse '"fo\\u03Bbo"').to eq "fo\u03bbo"
      expect(json_string.parse '"fo\\fo"').to eq "fo\fo"
      expect(json_string.parse '"fo\\ro"').to eq "fo\ro"
      expect(json_string.parse '"fo\\\\o"').to eq "fo\\o"
      expect(json_string.parse '"fo\\/o"').to eq "fo/o"
      expect(json_string.parse '"fo\\bo"').to eq "fo\bo"
    end
  end

  describe "#number" do
    it "parses numbers" do
      expect(number.parse "0").to eq 0
      expect(number.parse "123").to eq 123
      expect(number.parse "123.456").to eq 123.456
      expect(number.parse "+123").to eq 123
      expect(number.parse "+123.456").to eq 123.456
      expect(number.parse "-123").to eq -123
      expect(number.parse "-123.456").to eq -123.456
      expect(number.parse "-123.456e2").to eq -12345.6
      expect(number.parse "-123.456e-2").to eq -1.23456
    end
  end

  describe "#array" do
    it "parses arrays with a variety of whitespacing options" do
      expect(array.parse "[]").to eq []
      expect(array.parse "[  ]").to eq []
      expect(array.parse "[null]").to eq [nil]
      expect(array.parse "[  null  ]").to eq [nil]
      expect(array.parse "[[], null, 10]").to eq [[], nil, 10]
      expect(array.parse "[[],null,10]").to eq [[], nil, 10]
      expect(array.parse "[  []  ,  null  ,  10  ]").to eq [[], nil, 10]
    end
  end

  describe "#object" do
    it "parses objects different type values" do
      expect(object.parse '{"foo": 10}').to eq({"foo" => 10})
      expect(object.parse '{"foo": null}').to eq({"foo" => nil})
      expect(object.parse '{"foo": {}}').to eq({"foo" => {}})
      expect(object.parse '{"foo": []}').to eq({"foo" => []})
      expect(object.parse '{"foo": true}').to eq({"foo" => true})
    end

    it "parses objects with a variety of whitespacing options" do
      expect(object.parse '{}').to eq({})
      expect(object.parse '{  }').to eq({})
      expect(object.parse '{"foo": "bar"}').to eq({"foo" => "bar"})
      expect(object.parse '{"foo":"bar"}').to eq({"foo" => "bar"})
      expect(object.parse '{  "foo"  :  "bar"  }').to eq({"foo" => "bar"})
      expect(object.parse '{"foo": "bar", "baz": "taz"}').to eq({"foo" => "bar", "baz" => "taz"})
      expect(object.parse '{"foo":"bar","baz":"taz"}').to eq({"foo" => "bar", "baz" => "taz"})
      expect(object.parse '{ "foo" : "bar" , "baz" : "taz" }').to eq({"foo" => "bar", "baz" => "taz"})
    end
  end
end
