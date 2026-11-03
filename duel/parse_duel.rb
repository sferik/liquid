# frozen_string_literal: true

require_relative "duel_helper"

# Parsing below the theme: the lexer and expressions, with the markup of
# performance/unit, and a storefront section (SECTION, in duel_helper.rb)
# in each error mode.

# The expressions of performance/unit/lexer_benchmark.rb.
LEXER_EXPRESSIONS = [
  "foo[1..2].baz",
  "12.0",
  "foo.bar.based",
  "21 - 62",
  "foo.bar.baz",
  "foo > 12",
  "foo < 12",
  "foo <= 12",
  "foo >= 12",
  "foo <> 12",
  "foo == 12",
  "foo != 12",
  "foo contains 12",
  "foo contains 'bar'",
  "foo != 'bar'",
  "'foo' contains 'bar'",
  "234089",
  "foo | default: -1",
].freeze

duel "lexer: tokenize expressions" do
  once { @scanner = StringScanner.new("") }
  LEXER_EXPRESSIONS.each do |expression|
    @scanner.string = expression
    Liquid::Lexer.tokenize(@scanner)
  end
end

# The markup of performance/unit/expression_benchmark.rb, by kind.
{
  "variable lookups" => [
    "article",
    "article.title",
    "article.title.size",
    "very_long_variable_name_2024_11_05",
    "very_long_variable_name_2024_11_05.size",
    "product.variants[0].price",
    "collections['frontpage'].products",
  ],
  "numbers" => [
    "0",
    "35",
    "1241891024912849",
    "3.5",
    "3.51214128409128",
    "12381902839.123819283910283",
    "123.456.789",
    "-123",
    "-12.33",
    "-405.231",
    "-0",
    "0.0",
    "0.0000000000000000000000",
    "0.00000000001",
  ],
  "ranges" => [
    "(1..30)",
    "(1...30)",
    "(1..30..5)",
    "(1.0...30.0)",
    "(1.........30)",
    "(1..foo)",
    "(foo..30)",
    "(foo..bar)",
    "(foo...bar...100)",
    "(foo...bar...100.0)",
  ],
}.each do |kind, markups|
  duel "expression: parse #{kind}" do
    once { @scanner = StringScanner.new("") }
    markups.each { |markup| Liquid::Expression.parse(markup, @scanner) }
  end
end

[:lax, :strict, :strict2].each do |mode|
  duel "parse: a collection section, #{mode}" do
    Liquid::Template.parse(SECTION, error_mode: mode)
  end
end

# A whole page's worth of section, so a cost per byte or per node grows
# into something measurable.
duel "parse: a 30 KB template" do
  once { @source = SECTION * 13 }
  Liquid::Template.parse(@source)
end

duel "parse: a liquid tag of 50 lines" do
  once do
    lines = Array.new(25) { |i| "assign total_#{i} = product.price | times: #{i + 1} | plus: 50\n  echo total_#{i} | money" }
    @source = "{%- liquid\n  #{lines.join("\n  ")}\n-%}"
  end
  Liquid::Template.parse(@source)
end
