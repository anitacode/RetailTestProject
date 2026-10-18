require "test_helper"
require "tempfile"
require "csv"

class LatestTrackingObservationTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @store = Store.create!(address: "Latest observation store")
    brand = Brand.create!(name: "Latest observation brand")
    @product = Product.create!(name: "Latest observation product", brand: brand)
    @time = Time.utc(2026, 1, 2, 12)
  end

  test "no history returns no observation for either category" do
    assert_nil latest_inventory
    assert_nil latest_price
  end

  test "inventory-only history preserves false without inventing a price" do
    observe(:inventory_presence, @time - 1, { present: true })
    current = observe(:inventory_presence, @time, { present: false })

    assert_equal current, latest_inventory
    assert_equal false, latest_inventory.value["present"]
    assert_nil latest_price
  end

  test "price-only history preserves zero without inventing inventory" do
    observe(:price_tracker, @time - 1, { amount: 10, currency: "USD" })
    current = observe(:price_tracker, @time, { amount: 0, currency: "USD" })

    assert_equal current, latest_price
    assert_equal 0, latest_price.value["amount"]
    assert_nil latest_inventory
  end

  test "interleaved histories advance independently" do
    inventory = observe(:inventory_presence, @time, { present: false })
    price = observe(:price_tracker, @time + 1, { amount: 12.5, currency: "USD" })
    assert_equal inventory, latest_inventory
    assert_equal price, latest_price

    inventory = observe(:inventory_presence, @time + 2, { present: true })
    assert_equal inventory, latest_inventory
    assert_equal price, latest_price

    price = observe(:price_tracker, @time + 3, { amount: 9, currency: "USD" })
    assert_equal inventory, latest_inventory
    assert_equal price, latest_price
  end

  test "older bulk observations inserted later do not become current" do
    inventory = observe(:inventory_presence, @time, { present: false })
    price = observe(:price_tracker, @time, { amount: 12, currency: "USD" })
    TrackingEvent.insert_all!([
      attributes(:inventory_presence, @time - 1, { present: true }),
      attributes(:price_tracker, @time - 1, { amount: 99, currency: "USD" })
    ])

    assert_equal inventory, latest_inventory
    assert_equal price, latest_price
  end

  test "CSV imported later cannot supersede a newer inventory observation or price" do
    inventory = observe(:inventory_presence, @time, { present: false })
    price = observe(:price_tracker, @time, { amount: 12, currency: "USD" })
    Tempfile.create(["older-observations", ".csv"]) do |file|
      file.write(CSV.generate_line(["Address", "Product Name", "Date", "Inventory Present"]))
      file.write(CSV.generate_line([@store.address, @product.name, "2025-12-31", "True"]))
      file.flush
      assert_equal({ processed: 1, inserted: 1 }, TrackingEvents::CsvImporter.new(file.path).call)
    end

    assert_equal inventory, latest_inventory
    assert_equal price, latest_price
  end

  test "equal observation times select the greater id independently" do
    observe(:inventory_presence, @time, { present: true })
    inventory = observe(:inventory_presence, @time, { present: false })
    observe(:price_tracker, @time, { amount: 12, currency: "USD" })
    price = observe(:price_tracker, @time, { amount: 10, currency: "USD" })

    assert_equal inventory, latest_inventory
    assert_equal price, latest_price
  end

  test "observations are isolated by both store and product" do
    inventory = observe(:inventory_presence, @time, { present: false })
    price = observe(:price_tracker, @time, { amount: 12, currency: "USD" })
    other_store = Store.create!(address: "Other observation store")
    other_product = Product.create!(name: "Other observation product", brand: @product.brand)
    [:inventory_presence, :price_tracker].each do |type|
      payload = type == :inventory_presence ? { present: true } : { amount: 99, currency: "USD" }
      TrackingEvent.create!(attributes(type, @time + 1, payload).merge(store_id: other_store.id))
      TrackingEvent.create!(attributes(type, @time + 1, payload).merge(product_id: other_product.id))
    end

    assert_equal inventory, latest_inventory
    assert_equal price, latest_price
  end

  test "undated observations never become current" do
    observe(:inventory_presence, nil, { present: true })
    observe(:price_tracker, nil, { amount: 99, currency: "USD" })
    assert_nil latest_inventory
    assert_nil latest_price
    inventory = observe(:inventory_presence, @time, { present: false })
    price = observe(:price_tracker, @time, { amount: 12, currency: "USD" })
    assert_equal inventory, latest_inventory
    assert_equal price, latest_price
  end

  test "invalid later payloads cannot displace valid observations" do
    inventory = observe(:inventory_presence, @time, { present: false })
    price = observe(:price_tracker, @time, { amount: 12, currency: "USD" })
    [[:inventory_presence, { present: nil }], [:price_tracker, { amount: -1, currency: "USD" }]].each do |type, payload|
      values = attributes(type, @time + 1, payload)
      refute TrackingEvent.new(values).valid?
      assert_raises(ActiveRecord::StatementInvalid) do
        TrackingEvent.transaction(requires_new: true) { TrackingEvent.insert_all!([values]) }
      end
    end
    assert_equal inventory, latest_inventory
    assert_equal price, latest_price
  end

  private

  def attributes(type, time, payload)
    { store_id: @store.id, product_id: @product.id, event_type: type, event_time: time, value: payload }
  end

  def observe(type, time, payload)
    TrackingEvent.create!(attributes(type, time, payload))
  end

  def latest_inventory
    TrackingEvent.latest_inventory(store_id: @store.id, product_id: @product.id)
  end

  def latest_price
    TrackingEvent.latest_price(store_id: @store.id, product_id: @product.id)
  end
end
