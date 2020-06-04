require "parsby"

module Parsby::Example
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
      string("(") > lazy { expression } < string(")")
    end

    def parenthetical_text
      join(
        empty \
          << string("(") \
          << join(many((lazy { parenthetical_text } | any_char).that_fail(string(")")))) \
          << string(")")
      )
    end

    def binary_expression(precedence = 0)
      (
        empty \
          << join(many((parenthetical_text | any_char).that_fail(choice(operators[precedence])))) \
          << choice(operators[precedence] || []) \
          << join(many((parenthetical_text | any_char).that_fail(eof | string(")"))))
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
end
