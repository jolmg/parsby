# Parsby

Parser combinator library for Ruby, based on Haskell's Parsec.

 - [Installation](#installation)
 - [Introduction](#introduction)
 - [`Parsby.new`](#parsbynew)
 - [Defining combinators](#defining-combinators)
 - [`ExpectationFailed`](#expectationfailed)
   - [Cleaning up the parse tree for the trace](#cleaning-up-the-parse-tree-for-the-trace)
   - [`splicer.start` combinator](#splicerstart-combinator)
 - [Parsing from a string, a file, a pipe, a socket, ...](#parsing-from-a-string-a-file-a-pipe-a-socket-)
 - [Comparing with Haskell's Parsec](#comparing-with-haskells-parsec)
 - [Development](#development)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'parsby'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install parsby

## Introduction

If you're already familiar with this type of library, you might prefer to
skip to [Comparing with Haskell's Parsec](#comparing-with-haskells-parsec),
and/or check-out the example parsers:

 - [CSV (RFC 4180 compliant)](lib/parsby/example/csv_parser.rb)
 - [JSON](lib/parsby/example/json_parser.rb)
 - [Lisp](lib/parsby/example/lisp_parser.rb)
 - [Arithmetic](lib/parsby/example/arithmetic_parser.rb)

Carrying on, this is a library used to define parsers by declaratively
describing a syntax using what's commonly referred to as combinators.
Parser combinators are functions that take parsers as inputs and/or return
parsers as outputs, i.e. they *combine* parsers into new parsers.

As an example, `between` is a combinator with 3 parameters: a parser for
what's to the left, one for what's to the right, and lastly one for what's
in-between them, and it returns a parser that, after parsing, returns the
result of the in-between parser:

```ruby
between(lit("<"), lit(">"), lit("foo")).parse "<foo>"
#=> "foo"
```

`lit` is a combinator that takes a string and returns a parser for
`lit`erally that string.

## `Parsby.new`

Now, normally one ought to be able to define parsers using just
combinators, but there are times when one might need more control. For
those times, the most raw way to define a parser is using `Parsby.new`.

Let's look at a slightly simplified pre-existing use:

```ruby
def lit(e, case_sensitive: true)
  Parsby.new do |c|
    a = c.bio.read e.length
    if case_sensitive ? a == e : a.to_s.downcase == e.downcase
      a
    else
      raise ExpectationFailed.new c
    end
  end
end
```

That's the `lit` combinator mentioned before. It takes a string argument
for what it `e`xpects to parse, and returns what was `a`ctually parsed if
it matches the expectation.

The block parameter `c` is a `Parsby::Context`. `c.bio` holds a
`Parsby::BackedIO`. The `parse` method of `Parsby` objects accepts ideally
any `IO` (and `String`s, which it turns into `StringIO`) and then wraps
them with `BackedIO` to give the `IO` the ability to backtrack.

## Defining combinators

If you look at the examples in this source, you'll notice that all combinators are defined with `define_combinator`. Strictly speaking, it's not necessary to use that to define combinators. You can do it with variable assignment or `def` syntax. Nevertheless, `define_combinator` is preferred because it automates the assignment of a label to the combinator. Consider these examples:

```ruby
define_combinator :between do |left, right, p|
  left > p < right
end

between(lit("<"), lit(">"), lit("foo")).label
#=> 'between(lit("<"), lit(">"), lit("foo"))'
```

If we use `def` instead of `define_combinator`, then the label would be
that assigned by the outermost combinator. In the following case, it would
be that assigned by `<`.

```ruby
def between(left, right, p)
  left > p < right
end

between(lit("<"), lit(">"), lit("foo")).label
=> '((lit("<") > lit("foo")) < lit(">"))'
```

If we're to wrap that parser in a new one, then the label would be simply
unknown.

```ruby
def between(left, right, p)
  Parsby.new {|c| (left > p < right).parse c }
end

between(lit("<"), lit(">"), lit("foo")).label.to_s
=> "<unknown>"
```

## `ExpectationFailed`

Here's an example of an error, when parsing fails:

```
pry(main)> Parsby::Example::LispParser.sexp.parse "(foo `(foo ,bar) 2.3 . . nil)"    
Parsby::ExpectationFailed: line 1:
  (foo `(foo ,bar) 2.3 . . nil)
                         |           * failure: char_in("([")
                         |           * failure: list
                         |          *| failure: symbol
                         |         *|| failure: nil
                         |        *||| failure: string
                         |       *|||| failure: number
                                 \\\||
                         |          *| failure: atom
                         |         *|| failure: abbrev
                                   \\|
                         |           * failure: sexp
                       V            *| success: lit(".")
                   \-/             *|| success: sexp
       \---------/                *||| success: sexp
   \-/                           *|||| success: sexp
  V                             *||||| success: char_in("([")
                                \\\\\|
  |                                  * failure: list
  |                                  * failure: sexp
```

As can be seen, Parsby manages a tree structure representing parsers and
their subparsers, with the information of where a particular parser began
parsing, where it ended, whether it succeeded or failed, and the label of
the parser.

It might be worth mentioning that when debugging a parser from an
unexpected `ExpectationFailed` error, the backtrace isn't really useful.
That's because the backtrace points to the code involved in parsing, not
the code involved in constructing the parsers, which succeeded, but is
where the problem typically lies. The tree-looking exception message above
is meant to somewhat substitute the utility of the backtrace in these
cases.

Relating to that, the right-most text are the labels of the corresponding
parsers. I find that labels that resemble the source code are quite useful,
just like the code location descriptions that appear right-most in
backtraces. It's because of this that I consider the use of
`define_combinator` more preferable than using `def` and explicitely
assigning labels.

### Cleaning up the parse tree for the trace

If you look at the source of the example lisp parser, you might note that
there are a lot more parsers in between those shown in the tree above.
`sexp` is not a direct child of `list`, for example, despite it appearing
as so. There are at least 6 ancestors/descendant parsers between `list` and
`sexp`. It'd be very much pointless to show them all. They convey little
additional information and their labels are very verbose.

### `splicer.start` combinator

The reason why they don't appear is because `splicer` is used to make the
tree look a little cleaner.

The name comes from JS's `Array.prototype.splice`, to which you can give a
starting position, and a count specifying the end, and it'll remove the
specified elements from an Array. We use `splicer` likewise, only it works
on parse trees. To show an example, here's a simplified definition of
`choice`:

```ruby
define_combinator :choice do |*ps|
  ps = ps.flatten

  ps.reduce(unparseable) do |a, p|
    a | p
  end
end
```

Let's fail it:

```
pry(main)> choice(lit("foo"), lit("bar"), lit("baz")).parse "qux"                                   
Parsby::ExpectationFailed: line 1:
  qux
  \-/    * failure: lit("baz")
  \-/   *| failure: lit("bar")
  \-/  *|| failure: lit("foo")
  |   *||| failure: unparseable
      \|||
  |    *|| failure: (unparseable | lit("foo"))
       \||
  |     *| failure: ((unparseable | lit("foo")) | lit("bar"))
        \|
  |      * failure: (((unparseable | lit("foo")) | lit("bar")) | lit("baz"))
  |      * failure: choice(lit("foo"), lit("bar"), lit("baz"))
```

Those parser intermediaries that use `|` aren't really making things any
clearer. Let's use `splicer` to remove those:

```ruby
    define_combinator :choice do |*ps|
      ps = ps.flatten

      splicer.start do |m|
        ps.reduce(unparseable) do |a, p|
          a | m.end(p)
        end
      end
    end
```

Let's fail it, again:

```
pry(main)> choice(lit("foo"), lit("bar"), lit("baz")).parse "qux"                                  
Parsby::ExpectationFailed: line 1:
  qux
  \-/   * failure: lit("baz")
  \-/  *| failure: lit("bar")
  \-/ *|| failure: lit("foo")
      \\|
  |     * failure: splicer.start((((unparseable | splicer.end(lit("foo"))) | splicer.end(lit("bar"))) | splicer.end(lit("baz"))))
  |     * failure: choice(lit("foo"), lit("bar"), lit("baz"))
```

Now, the only issue left is that `define_combinator` wraps the result of
the parser in another parser. Let's disable that wrapping by passing `wrap:
false` to it:

```ruby
    define_combinator :choice, wrap: false do |*ps|
      ps = ps.flatten

      splicer.start do |m|
        ps.reduce(unparseable) do |a, p|
          a | m.end(p)
        end
      end
    end
```

Let's fail it, again:

```
pry(main)> choice(lit("foo"), lit("bar"), lit("baz")).parse "qux"                                  
Parsby::ExpectationFailed: line 1:
  qux
  \-/   * failure: lit("baz")
  \-/  *| failure: lit("bar")
  \-/ *|| failure: lit("foo")
      \\|
  |     * failure: choice(lit("foo"), lit("bar"), lit("baz"))
```

## Parsing from a string, a file, a pipe, a socket, ...

Any `IO` ought to work (unit tests currently have only checked pipes,
though). When you pass a string to `#parse` it wraps it with `StringIO`
before using it.

## Recursive parsers with `lazy`

If we try to define a recursive parser using combinators like so:

```ruby
define_combinator :value do
  list | lit("foo")
end

define_combinator :list do
  between(lit("["), lit("]"), sep_by(lit(","), spaced(value)))
end

value
#=> SystemStackError: stack level too deep
```

We get a stack overflow.

This isn't a problem in Haskell because the language evaluates lazily by
default. This allows it to define recursive parsers without even thinking
about it.

In Ruby's case, we need to be explicit about our laziness. For that,
there's `lazy`. We just need to wrap one of the expressions in the
recursive loop with it. It could be the `value` call in `list`; it could be
`list` call in `value`; it could be the whole of `value`. It really doesn't
matter.

```ruby
define_combinator :value do
  lazy { list | lit("foo") }
end

define_combinator :list do
  between(lit("["), lit("]"), sep_by(lit(","), spaced(value)))
end

value.parse "[[[[foo, foo]]]]"
#=> [[[["foo", "foo"]]]]
```

## Comparing with Haskell's Parsec

Although there's more to this library than its similarities with Parsec,
they are pretty similar:

```ruby
# Parsby                                 # Parsec
                                         #
foo.then {|x| bar x }                    # foo >>= \x -> bar x
                                         #
foo | bar                                # foo <|> bar
                                         #
foobar = Parsby.new do |c|               # foobar = do
  x = foo.parse c                        #   x <- foo
  bar(x).parse c                         #   bar x
end                                      #
                                         #
lit("(") > foo < lit(")")                # string "(" *> foo <* string ")"
                                         #
lit("5").fmap {|n| n.to_i + 1 }          # fmap (\n -> read n + 1) (string "5")
                                         #
group(                                   #
  w,                                     #
  group(x, y),                           #
  z,                                     #
).fmap do |(wr, (xr, yr), zr)|           #
  Foo.new(wr, Bar.new(xr, yr), zr)       # Foo <$> w <*> (Bar <$> x <*> y) <*> z
end                                      #
                                         #
                                         # -- Means the same, but this
                                         # -- raises an error in Haskell
                                         # -- because it requires an
                                         # -- infinite type [[[[...]]]]
recursive do |p|                         # fix $ \p ->
  between(lit("("), lit(")"),            #  between (string "(") (string ")") $
    single(p) | pure([])                 #    ((:[]) <$> p) <|> pure []
  end                                    #
end                                      #
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then,
run `rake spec` to run the tests. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

`bin/console` includes `Parsby::Combinators` into the top-level so the
combinators and `define_combinator` are available directly from the prompt.
It also defines `reload!` to quickly load changes made to the source.

To install this gem onto your local machine, run `bundle exec rake
install`.
