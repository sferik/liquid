# frozen_string_literal: true

require_relative "duel_helper"

# The four Shopify themes in performance/tests, which `rake benchmark`
# runs too: every page template and its layout, parsed, and rendered with
# the theme's tags and filters against the vision database. Rendering
# parses each theme once, untimed.

theme_names.each do |name|
  duel "theme: parse #{name}" do
    once { @sources = theme_sources(name) }
    parse_theme(@sources)
  end

  duel "theme: render #{name}" do
    once { build_theme(name) }
    render_theme
  end
end

# Every theme at once, in each of the error modes: the lax parser that
# the default environment uses, and the strict ones, which parse tag and
# variable markup with Liquid::Parser instead of regular expressions.
[:lax, :strict, :strict2].each do |mode|
  duel "theme: parse all four, #{mode}" do
    once { @sources = theme_names.map { |theme| theme_sources(theme) } }
    @sources.each { |sources| parse_theme(sources, error_mode: mode) }
  end
end

duel "theme: parse all four, with line numbers" do
  once { @sources = theme_names.map { |theme| theme_sources(theme) } }
  @sources.each { |sources| parse_theme(sources, line_numbers: true) }
end

# The tokenizer alone, as ThemeRunner#tokenize runs it.
duel "tokenizer: split all four themes" do
  once do
    @sources = theme_names.flat_map { |theme| theme_sources(theme).values }
    @scanner = StringScanner.new("")
  end
  @sources.each do |source|
    tokenizer = Liquid::Tokenizer.new(source: source, string_scanner: @scanner, line_numbers: true)
    while tokenizer.shift; end
  end
end
