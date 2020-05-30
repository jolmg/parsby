require "parsby"

module ArithmeticParser
  include Parsby::Combinators
  extend self

  def expression
    binary_expression | decimal
  end

  BinaryExpression = Struct.new :left, :op, :right

  def binary_expression
    Parsby.new do |io|
      left_text = take_until(operator).parse io
      op = operator.parse io
      right_text = take_until(eof).parse io
      left = expression.parse left_text
      right = expression.parse right_text
      BinaryExpression.new left, op, right
    end
  end

  def operator
    string("+") | string("-")
  end
end
