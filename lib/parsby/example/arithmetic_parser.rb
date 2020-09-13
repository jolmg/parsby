require "parsby"

module Parsby::Example
  module ArithmeticParser
    include Parsby::Combinators
    extend self

    def parse(io)
      expr.parse io
    end

    def self.define_binary_op(name, op)
      define_combinator name do |left_subexpr, right_subexpr|
        group(left_subexpr, spaced(ilit(op)), right_subexpr)
      end
    end

    define_binary_op :add_op, "+"
    define_binary_op :sub_op, "-"
    define_binary_op :mul_op, "*"
    define_binary_op :div_op, "/"
    define_binary_op :exp_op, "^"

    def self.define_unary_op(name, op)
      define_combinator name do |subexpr|
        group(ilit(op), ws > subexpr)
      end
    end

    define_unary_op :neg_op, "-"
    define_unary_op :pos_op, "+"

    # hpe - higher precedence level
    # spe - same precedence level

    def right_associative_binary_precedence_level(hpe, operators)
      recursive do |spe|
        choice(
          *operators.map do |op|
            send(op, hpe, spe)
          end,
          hpe,
        )
      end
    end

    def left_associative_binary_precedence_level(hpe, operators)
      reduce hpe do |left_expr|
        choice(
          *operators.map do |op|
            send(op, pure(left_expr), hpe)
          end
        )
      end
    end

    def unary_precedence_level(hpe, operators)
      recursive do |spe|
        choice(
          *operators.map do |op|
            send(op, spe)
          end,
          hpe,
        )
      end
    end

    define_combinator :expr do
      lazy do
        e = choice(
          decimal_fraction,
          between(lit("("), lit(")"), expr),
        )

        e = right_associative_binary_precedence_level(e, [
          :exp_op,
        ])

        e = unary_precedence_level(e, [
          :neg_op,
          :pos_op,
        ])

        e = left_associative_binary_precedence_level(e, [
          :mul_op,
          :div_op,
        ])

        e = left_associative_binary_precedence_level(e, [
          :add_op,
          :sub_op,
        ])
      end
    end
  end
end
