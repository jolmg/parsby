require "parsby"

module Parsby::Example
  module ArithmeticParser
    include Parsby::Combinators
    extend self

    def parse(io)
      (expression < eof).parse io
    end

    def expression(precedence = 0)
      between(whitespace, whitespace, choice(
        parenthetical_expression,
        *(precedence...operators.length).map {|preced| binary_expression(preced)},
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
          << parsby(&:pos) \
          << join(many((parenthetical_text | any_char).that_fail(choice(operators[precedence])))) \
          << choice(operators[precedence] || []) \
          << parsby(&:pos) \
          << join(many((parenthetical_text | any_char).that_fail(eof | string(")"))))
      ).fmap do |(left_pos, left_text, op, right_pos, right_text)|
        [
          expression(precedence + 1)
            .on_catch {|e| e.modify! at: e.opts[:at] + left_pos}
            .parse(left_text),
          op,
          (expression(precedence) < eof)
            .on_catch {|e| e.modify! at: e.opts[:at] + right_pos}
            .parse(right_text),
        ]
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
