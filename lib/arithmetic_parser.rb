require "parsby"

module ArithmeticParser
  include Parsby::Combinators
  extend self

  BinaryExpression = Struct.new :left, :op, :right

  def expression(precedence = 0)
    between(whitespace, whitespace, choice(
      parenthetical_expression,
      binary_expression(precedence),
      decimal,
    ))
  end

  def parenthetical_expression
    string("(") > expression < string(")")
  end

  def parenthetical_text
    (
      collect \
        & string("(") \
        & take_until(string(")"), with: parenthetical_text | any_char) \
        & string(")")
    ).fmap(&:join)
  end

  def binary_expression(precedence = 0)
    (
      collect \
        & take_until(choice(operators[precedence]), with: parenthetical_text | any_char) \
        & choice(operators[precedence] || []) \
        & take_until(eof | string(")"), with: parenthetical_text | any_char)
    ).fmap do |(left_text, op, right_text)|
      BinaryExpression.new(
        expression(precedence + 1).parse(left_text),
        op,
        expression(precedence + 1).parse(right_text),
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
