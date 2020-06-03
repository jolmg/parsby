RSpec.describe Parsby::Example::ArithmeticParser do
  describe "#expression" do
    it "parses simple sums"
    it "understands parenthesis"
  end

  describe "#operators" do
    it "contains operators by precedence level"
  end

  describe "#parenthetical_text" do
    it "takes everything between parentheses, ignoring embedded ones"
  end

  describe "#parenthetical_expression" do
    it "returns expression inside parentheses"
  end

  describe "#binary_expression" do
    it "parses binary expression of give precedence level"
  end
end
