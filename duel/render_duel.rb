# frozen_string_literal: true

require_relative "duel_helper"

# Rendering, a piece at a time: variable lookups, filters, each of the
# tags that loop or branch, and partials. Each template is parsed once,
# untimed, and rendered with render!, so an error fails the benchmark.

duel "render: a collection section" do
  once do
    parse_template(SECTION)
    @assigns = {
      "collection" => {
        "title" => "Summer",
        "description" => "<p>Light and bright.</p>",
        "image" => "summer.jpg",
        "products_count" => 24,
        "products" => catalog(24),
      },
      "settings" => {},
    }
    render_template
  end
  render_template
end

duel "render: variable lookups" do
  once do
    parse_template(<<~LIQUID)
      {{ product.title }} {{ product.vendor }} {{ product.variants.first.title }} {{ product.variants[1].price }}
      {{ product.variants.last.id }} {{ product.tags.size }} {{ product.tags[0] }} {{ shop.name }} {{ shop.address.city }}
      {{ shop['currency'] }} {{ product["handle"] }} {{ missing.everything }} {{ product.variants.size }}
    LIQUID
    @assigns = { "product" => catalog(1).first, "shop" => { "name" => "Snowdevil", "currency" => "CAD", "address" => { "city" => "Ottawa" } } }
  end
  render_template
end

# A drop, as an app hands Liquid its own objects.
class ProductDrop < Liquid::Drop
  def initialize(product)
    super()
    @product = product
  end

  def title = @product["title"]
  def price = @product["price"]
  def available = @product["available"]
  def tags = @product["tags"]
end

duel "render: drop methods" do
  once do
    parse_template("{% for product in products %}{{ product.title }} {{ product.price }} {{ product.available }} {{ product.tags | join: ', ' }}\n{% endfor %}")
    @assigns = { "products" => catalog(20).map { |product| ProductDrop.new(product) } }
  end
  render_template
end

duel "render: a chain of string filters" do
  once do
    parse_template(<<~LIQUID)
      {% for product in products %}
      {{ product.title | downcase | replace: 'product', 'item' | capitalize | truncate: 40 | escape }}
      {{ product.description | strip_html | strip_newlines | truncatewords: 12 | append: ' (more)' }}
      {{ product.handle | prepend: '/products/' | url_encode }} {{ product.vendor | upcase | slice: 0, 3 }}
      {{ product.title | split: ': ' | last | remove: 'the ' | lstrip | size }}
      {% endfor %}
    LIQUID
    @assigns = { "products" => catalog(10) }
  end
  render_template
end

duel "render: array filters" do
  once do
    parse_template(<<~LIQUID)
      {{ products | map: 'vendor' | uniq | sort | join: ', ' }}
      {{ products | where: 'available' | size }} {{ products | where: 'type', 'Hat' | map: 'title' | first }}
      {{ products | sort: 'price' | map: 'price' | last }} {{ products | map: 'tags' | concat: extra | compact | size }}
      {{ products | reverse | map: 'handle' | first }} {{ products | map: 'price' | sum }}
      {{ products | sort_natural: 'title' | map: 'id' | join: '-' | slice: 0, 20 }}
    LIQUID
    @assigns = { "products" => catalog(50), "extra" => ["a", nil, "b"] }
  end
  render_template
end

duel "render: math and default filters" do
  once do
    parse_template(<<~LIQUID)
      {% for product in products %}{{ product.price | divided_by: 100.0 | round: 2 }} {{ product.price | times: 3 | minus: 1 | modulo: 7 }}
      {{ product.compare_at_price | default: product.price | at_least: 1500 | at_most: 9000 | plus: 0.5 | ceil }} {{ product.id | abs | floor }}
      {% endfor %}
    LIQUID
    @assigns = { "products" => catalog(20) }
  end
  render_template
end

duel "render: a for loop of 100, with forloop" do
  once do
    parse_template(<<~LIQUID)
      {% for product in products %}{{ forloop.index }}/{{ forloop.length }} {{ product.title }}{% if forloop.first %} first{% endif %}{% unless forloop.last %},{% endunless %} {{ forloop.rindex0 }}
      {% endfor %}
    LIQUID
    @assigns = { "products" => catalog(100) }
  end
  render_template
end

duel "render: a for loop with limit, offset and reversed" do
  once do
    parse_template("{% for product in products limit: 30 offset: 10 reversed %}{{ product.id }} {% endfor %}{% for i in (1..50) %}{{ i }}{% break %}{% endfor %}")
    @assigns = { "products" => catalog(100) }
  end
  render_template
end

duel "render: nested for loops, with break and continue" do
  once do
    parse_template(<<~LIQUID)
      {% for product in products %}{% for variant in product.variants %}{% if variant.available == false %}{% continue %}{% endif %}{{ forloop.parentloop.index }}.{{ forloop.index }} {{ variant.title }}{% if variant.price > 1400 %}{% break %}{% endif %}
      {% endfor %}{% endfor %}
    LIQUID
    @assigns = { "products" => catalog(40) }
  end
  render_template
end

duel "render: tablerow" do
  once do
    parse_template("{% tablerow product in products cols: 4 %}{{ tablerowloop.col }} {{ product.title }}{% endtablerow %}")
    @assigns = { "products" => catalog(40) }
  end
  render_template
end

duel "render: if, elsif and else, with and and or" do
  once do
    parse_template(<<~LIQUID)
      {% for product in products %}{% if product.available and product.price < 3000 %}cheap{% elsif product.available or product.compare_at_price %}ok{% elsif product.vendor == 'Acme' %}acme{% else %}no{% endif %}
      {% if product.tags contains 'sale' %}sale{% endif %}{% if product.title != blank and product.compare_at_price > product.price %}deal{% endif %}{% unless product.type == 'Hat' %}!{% endunless %}
      {% endfor %}
    LIQUID
    @assigns = { "products" => catalog(50) }
  end
  render_template
end

duel "render: case and when" do
  once do
    parse_template(<<~LIQUID)
      {% for product in products %}{% case product.vendor %}{% when 'Acme' %}A{% when 'Globex', 'Initech' %}G{% when 'Umbrella' or 'Hooli' %}U{% else %}?{% endcase %}{% case product.id | modulo: 3 %}{% when 0 %}zero{% when 1 %}one{% else %}two{% endcase %}
      {% endfor %}
    LIQUID
    @assigns = { "products" => catalog(50) }
  end
  render_template
end

duel "render: assign, capture, increment and cycle" do
  once do
    parse_template(<<~LIQUID)
      {% for product in products %}{% assign price = product.price | divided_by: 100 %}{% capture line %}{{ product.title }}: {{ price }}{% endcapture %}{{ line | size }} {% increment counter %} {% cycle 'a', 'b', 'c' %}{% assign total = total | plus: price %}
      {% endfor %}{{ total }}
    LIQUID
    @assigns = { "products" => catalog(50) }
  end
  render_template
end

duel "render: whitespace control and comments" do
  once do
    parse_template(<<~LIQUID)
      {%- for product in products -%}
        {%- comment -%} a card {%- endcomment -%}
        {%- # the title -%}
        {{- product.title -}}
        {%- if product.available -%} yes {%- endif -%}
      {%- endfor -%}
    LIQUID
    @assigns = { "products" => catalog(50) }
  end
  render_template
end

# Partials, served from memory. The template keeps what it parses of a
# partial in its registers, so these time rendering it. The last one
# parses it too, as the first render of a template does, with a new
# context each time.
PARTIALS = {
  "product-card" => <<~LIQUID,
    <div class="card"><a href="/products/{{ product.handle }}">{{ product.title | escape }}</a>
    {% if product.available %}{{ product.price | divided_by: 100.0 }}{% else %}Sold out{% endif %}</div>
  LIQUID
  "price" => "{{ price | divided_by: 100.0 | round: 2 | prepend: currency }}",
}.freeze

def partials_file_system = MemoryFileSystem.new(PARTIALS)

duel "render: render a partial for each product" do
  once do
    parse_template("{% render 'product-card' for products as product %}")
    @assigns = { "products" => catalog(30) }
    @template.registers[:file_system] = partials_file_system
  end
  render_template
end

duel "render: render a partial with arguments" do
  once do
    parse_template("{% for product in products %}{% render 'price', price: product.price, currency: '$' %}{% endfor %}")
    @assigns = { "products" => catalog(30) }
    @template.registers[:file_system] = partials_file_system
  end
  render_template
end

duel "render: include a partial in a loop" do
  once do
    parse_template("{% for product in products %}{% include 'product-card' %}{% endfor %}")
    @assigns = { "products" => catalog(30) }
    @template.registers[:file_system] = partials_file_system
  end
  render_template
end

duel "render: parse and render partials in a new context" do
  once do
    parse_template("{% render 'product-card' for products as product %}{% include 'price', price: 1999, currency: '$' %}")
    @products = catalog(10)
  end
  context = Liquid::Context.build(environments: { "products" => @products }, registers: { file_system: partials_file_system }, rethrow_errors: true)
  @template.render!(context)
end
