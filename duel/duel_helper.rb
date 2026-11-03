# frozen_string_literal: true

# The Shopify-style themes, tags, filters and database that the theme
# runner in performance/ uses. Each version's lib/ has already loaded
# Liquid, so this requires only the theme's own code, not
# performance/shopify/liquid.rb, which would load this checkout's
# lib/liquid over the baseline's, and registers it with an environment of
# its own instead of the default one.
['comment_form', 'paginate', 'json_filter', 'money_filter', 'shop_filter', 'tag_filter', 'weight_filter', 'database'].each do |file|
  require_relative "../performance/shopify/#{file}"
end

THEMES_DIR = File.expand_path("../performance/tests", __dir__)

THEME_ENVIRONMENT = Liquid::Environment.build do |environment|
  environment.register_tag("paginate", Paginate)
  environment.register_tag("form", CommentForm)
  environment.register_filters([JsonFilter, MoneyFilter, WeightFilter, ShopFilter, TagFilter])
end

# A theme's templates, read once, as { "product" => source, ... }. Its
# layout is "theme".
def theme_sources(name)
  Dir[File.join(THEMES_DIR, name, "*.liquid")].sort.to_h do |path|
    [File.basename(path, ".liquid"), File.read(path)]
  end
end

def theme_names = Dir[File.join(THEMES_DIR, "*")].sort.map { |path| File.basename(path) }

def parse_theme(sources, **options)
  sources.each_value { |source| Liquid::Template.parse(source, environment: THEME_ENVIRONMENT, **options) }
end

# A theme's pages, parsed, as ThemeRunner sets them up: each page is
# rendered, then the layout around it, with the database as assigns.
def build_theme(name)
  sources = theme_sources(name)
  @layout = Liquid::Template.parse(sources.delete("theme"), environment: THEME_ENVIRONMENT)
  @pages = sources.map do |page, source|
    template = Liquid::Template.parse(source, environment: THEME_ENVIRONMENT)
    template.assigns["page_title"] = "Page title"
    template.assigns["template"] = page
    template
  end
  @assigns = Database.tables.dup
end

def render_theme
  @pages.each do |page|
    @assigns["content_for_layout"] = page.render!(@assigns)
    @layout.render!(@assigns)
  end
end

# A collection page's product grid: every kind of tag and output that a
# section has, so the parsers of each are in the mix. The parse and
# render benchmarks share it.
SECTION = <<~LIQUID
  {%- assign sale_count = 0 -%}
  {% capture heading %}{{ collection.title | upcase }} ({{ collection.products_count }} products){% endcapture %}
  <h1>{{ heading | strip | escape }}</h1>
  {% if collection.description != blank and collection.image %}
    <div class="rte">{{ collection.description | strip_html | truncatewords: 40, "..." }}</div>
  {% elsif collection.products_count > 0 or settings.show_empty %}
    <p>{{ "collections.general.count" | default: "Products" | append: ": " }}{{ collection.products_count }}</p>
  {% else %}
    <p class="empty">{{ 'collections.general.no_matches' | default: "Nothing here yet" }}</p>
  {% endif %}
  <ul class="grid">
  {% for product in collection.products limit: 24 offset: 0 %}
    <li class="{% cycle 'odd', 'even' %}{% if forloop.first %} first{% endif %}{% if forloop.last %} last{% endif %}">
      <a href="{{ product.url | default: '#' }}" title="{{ product.title | escape }}">
        <img src="{{ product.featured_image | default: 'no-image.gif' | prepend: '/files/' }}" alt="{{ product.title | escape }}">
        <span>{{ product.title | truncate: 30 }}</span>
      </a>
      {% case product.type %}
        {% when 'Shirt', 'Hat' %}<span class="badge">Wear it</span>
        {% when 'Bag' %}<span class="badge">Carry it</span>
        {% else %}<span class="badge">{{ product.type | downcase }}</span>
      {% endcase %}
      {% unless product.available %}<span class="sold-out">Sold out</span>{% endunless %}
      {% if product.compare_at_price > product.price %}
        {%- assign sale_count = sale_count | plus: 1 -%}
        <s>{{ product.compare_at_price | divided_by: 100.0 | round: 2 }}</s>
      {% endif %}
      <span class="price">{{ product.price | times: 1.0 | divided_by: 100 | round: 2 | prepend: "$" }}</span>
      {% for tag in product.tags %}{% if tag contains 'sale' %}<em>{{ tag }}</em>{% else %}{{ tag | capitalize }}{% endif %}{% unless forloop.last %}, {% endunless %}{% endfor %}
      {%- liquid
        assign variant = product.variants | first
        if variant.available
          echo variant.title | append: ' in stock'
        endif
      -%}
    </li>
  {% else %}
    <li>No products</li>
  {% endfor %}
  </ul>
  {% comment %}How many were on sale.{% endcomment %}
  <p>{{ sale_count }} on sale. {% raw %}{{ not liquid }}{% endraw %}</p>
  {% tablerow product in collection.products cols: 4 limit: 8 %}{{ product.title | split: ':' | first }}{% endtablerow %}
LIQUID

# Partials, from memory, as an app's file system would serve them.
class MemoryFileSystem
  def initialize(templates)
    @templates = templates
  end

  def read_template_file(template_path)
    @templates.fetch(template_path)
  end
end

# A catalog of this many products, the same every time.
def catalog(count)
  vendors = ["Acme", "Globex", "Initech", "Umbrella", "Hooli"]
  types = ["Shirt", "Shoes", "Hat", "Bag"]
  Array.new(count) do |i|
    {
      "id" => i + 1,
      "title" => "Product #{i + 1}: the #{types[i % 4].downcase} you'll want <for> everyday & more",
      "handle" => "product-#{i + 1}",
      "vendor" => vendors[i % 5],
      "type" => types[i % 4],
      "price" => 1000 + ((i * 739) % 9000),
      "compare_at_price" => i.even? ? 12_000 : nil,
      "available" => i % 7 != 0,
      "tags" => ["sale", "new", "summer", "cotton", "limited"].rotate(i).first(3),
      "description" => "<p>A <strong>well-made</strong> #{types[i % 4].downcase}, with a fit that lasts.</p>" * 3,
      "variants" => Array.new(3) do |v|
        { "id" => ((i + 1) * 10) + v, "title" => ["Small", "Medium", "Large"][v], "price" => 1000 + (v * 250), "available" => v != 1 }
      end,
    }
  end
end

# Parses source in the default environment, and keeps it for
# #render_template.
def parse_template(source, **options)
  @template = Liquid::Template.parse(source, **options)
end

# Renders the template from #parse_template, raising on any error, so a
# benchmark that stops rendering what it should fails instead of timing
# an error message.
def render_template(assigns = @assigns || {}, **options)
  @template.render!(assigns, **options)
end
