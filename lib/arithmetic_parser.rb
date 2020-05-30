require "parsby"

module ArithmeticParser
  include Parsby::Combinators
  extend self

  BinaryExpression = Struct.new :left, :op, :right

  def expression
    whitespace > (binary_expression | decimal) < whitespace
  end

  def parenthetical_expression
    string("(") > expression < string(")")
  end

  def parenthetical_text
    collect \
      & string("(") \
      & take_until(string(")"), with: parenthetical_text | any_char) \
      & string(")")
  end

  def binary_expression(precedence)
    (
      collect \
        & take_until(choice(operators[precedence]), with: parenthetical_text | any_char) \
        & choice(operators[precedence]) \
        & take_until(eof | string(")"), with: parenthetical_text | any_char)
    ).fmap do |(left_text, op, right_text)|
      BinaryExpression.new(
        expression.parse(left_text),
        op,
        expression.parse(right_text),
      )
    end
  end

  def operators
    [
      [string("+"), string("-")],
      [string("*"), string("/")],
      [string("^")],
    ]
  end
end
