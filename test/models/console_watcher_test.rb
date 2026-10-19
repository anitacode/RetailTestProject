require "test_helper"
require "stringio"

class ConsoleWatcherTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @store = Store.create!(address: "Watcher store")
    brand = Brand.create!(name: "Watcher brand")
    @product = Product.create!(name: "Watcher product", brand: brand)
    @output = StringIO.new
    @watcher = TrackingEvents::ConsoleWatcher.new(store_id: @store.id, product_id: @product.id, output: @output)
    @time = Time.current
  end

  test "reports initial unknowns and independent changes including false and zero" do
    @watcher.poll
    assert_equal "Inventory: unknown (initial)\nCurrent price: unknown (initial)\n", drain
    observe(:inventory_presence, { quantity: 0 })
    observe(:price_tracker, { amount: 0, currency: "USD" })
    @watcher.poll
    assert_equal "Inventory: unknown -> out of stock (0)\nCurrent price: unknown -> 0 USD\n", drain
    observe(:inventory_presence, { quantity: 1 }, @time + 1)
    @watcher.poll
    assert_equal "Inventory: out of stock (0) -> in stock (1)\n", drain
  end

  test "shows quantity and reports quantity changes while remaining in stock" do
    observe(:inventory_presence, { quantity: 15 })
    @watcher.poll
    assert_includes @output.string, PASTEL.bright_white.on_green("in stock (15)")
    assert_includes drain, "Inventory: in stock (15) (initial)"

    observe(:inventory_presence, { quantity: 10 }, @time + 1)
    @watcher.poll
    assert_equal "Inventory: in stock (15) -> in stock (10)\n", drain
    observe(:inventory_presence, { quantity: -2 }, @time + 2)
    @watcher.poll
    assert_includes @output.string, PASTEL.bright_white.on_red("out of stock (-2)")
    assert_equal "Inventory: in stock (10) -> out of stock (-2)\n", drain
  end

  test "ignores repeats older bulk imports and undated observations" do
    observe(:price_tracker, { amount: 12, currency: "USD" })
    @watcher.poll
    drain
    observe(:price_tracker, { amount: 12.0, currency: "USD" }, @time + 1)
    TrackingEvent.insert_all!([
      { store_id: @store.id, product_id: @product.id, event_type: "price_tracker", event_time: @time - 1, value: { amount: 99, currency: "USD" } }
    ])
    observe(:inventory_presence, { quantity: 1 }, nil)
    @watcher.poll
    assert_equal "", drain
    observe(:price_tracker, { amount: 12, currency: "EUR" }, @time + 2)
    @watcher.poll
    assert_equal "Current price: 12.0 USD -> 12 EUR\n", drain
  end

  private

  def observe(type, value, time = @time)
    TrackingEvent.create!(store: @store, product: @product, event_type: type, event_time: time, value: value)
  end

  def drain
    text = PASTEL.strip(@output.string)
    @output.truncate(0)
    @output.rewind
    text
  end
end
