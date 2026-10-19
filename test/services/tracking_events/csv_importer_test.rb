require "test_helper"
require "tempfile"

class TrackingEvents::CsvImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @store = Store.create!(address: "Importer test address")
    @brand = Brand.create!(name: "Importer test brand")
    @product = Product.create!(name: "Importer test product", brand: @brand)
  end

  test "imports alert only on new observations without backfilling historical pairs" do
    2.times do |index|
      TrackingEvent.create!(store: @store, product: @product, alert_eligible: false,
                            event_time: Date.new(2024, 1, index + 1), value: { quantity: 0 })
    end
    import([row(inventory: "False")])
    assert_equal 0, Alert.count
    import([row(inventory: "False", date: "2025-01-03")])
    assert_equal 1, Alert.count
    assert Alert.first.previous_event.alert_eligible?
    assert Alert.first.triggering_event.alert_eligible?
  end

  test "imports full batches and the final partial batch with bounded queries" do
    statements = []
    subscriber = ->(*args) { statements << args.last[:sql] unless args.last[:cached] }

    assert_difference "TrackingEvent.count", 20005 do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        import(Array.new(20005) { row })
      end
    end

    assert_equal (20005.to_f / batch_size).ceil, statements.count { |sql| sql.match?(/INSERT INTO "tracking_events"/) }
    assert_equal 2 * (20005.to_f / batch_size).ceil, statements.count { |sql| sql.match?(/SELECT .* FROM "(?:stores|products)"/) }
    event = TrackingEvent.order(:id).last
    assert_equal @store.id, event.store_id
    assert_equal @product.id, event.product_id
    assert_equal Date.new(2025, 1, 2), event.event_time.to_date
    assert event.created_at.present?
    assert event.updated_at.present?
  end

  test "converts legacy boolean observations to placeholder quantities" do
    rows = ["true", "TRUE", "t", "T", "1", "True", "False", "0", ""].map { |value| row(inventory: value) }

    assert_difference "TrackingEvent.count", 9 do
      import(rows)
    end
    assert_equal [true] * 6 + [false] * 3, TrackingEvent.order(:id).pluck(:inventory_present)
    assert_equal ([true] * 6 + [false] * 3).map { |value| { "quantity" => (value ? 1 : 0) } },
                 TrackingEvent.order(:id).pluck(:value)
  end

  test "all 10000 distinct rows retain their store product date and inventory values" do
    rows, expected = distinct_rows(10000)

    assert_import_matches(rows, expected)
  end

  test "missing references roll back earlier batches and preserve existing events" do
    existing = TrackingEvent.create!(store: @store, product: @product, value: { quantity: 9 })
    [{ address: "Missing" }, { product: "Missing" }].each do |invalid|
      updates = []
      rows = Array.new(batch_size) { row } + [row(**invalid), row]
      assert_no_difference "TrackingEvent.count" do
        error = assert_raises(TrackingEvents::CsvImporter::InvalidRow) do
          import(rows) { |counts| updates << counts }
        end
        assert_equal batch_size + 2, error.record_number
        assert_includes error.message, "not found"
        assert_includes error.message, "Missing"
      end
      assert_equal [existing.id], TrackingEvent.pluck(:id)
      assert_equal [{ processed: batch_size, inserted: batch_size }], updates
    end
  end

  test "missing reference within the first batch rejects all rows" do
    assert_no_difference "TrackingEvent.count" do
      error = assert_raises(TrackingEvents::CsvImporter::InvalidRow) do
        import([row, row(product: "Missing"), row])
      end
      assert_equal 3, error.record_number
      assert_includes error.message, "product not found"
    end
  end

  test "empty files create no events" do
    assert_no_difference("TrackingEvent.count") { import([]) }
  end

  test "record numbers count quoted multiline fields as one CSV record" do
    @store.update!(address: "First line\nSecond line")
    error = assert_raises(TrackingEvents::CsvImporter::InvalidRow) do
      import([row, row(product: "Missing")])
    end
    assert_equal 3, error.record_number
  end

  test "an invalid date fails before inserting the current batch" do
    assert_no_difference "TrackingEvent.count" do
      error = assert_raises(TrackingEvents::CsvImporter::InvalidRow) { import([row, row(date: "invalid")]) }
      assert_equal 3, error.record_number
      assert_includes error.message, 'invalid Date "invalid"'
    end
  end

  test "a later invalid date rolls back earlier batches and preserves existing events" do
    existing = TrackingEvent.create!(store: @store, product: @product, event_time: Date.new(2024, 1, 1), inventory_present: true, value: { quantity: 1 })
    rows = Array.new(batch_size) { row } + [row(date: "invalid")]

    assert_no_difference "TrackingEvent.count" do
      assert_raises(TrackingEvents::CsvImporter::InvalidRow) { import(rows) }
    end
    assert_equal [existing.id], TrackingEvent.pluck(:id)
  end

  test "a database error in a later batch rolls back the entire import" do
    # This constraint exists only within this test's transaction.
    TrackingEvent.connection.add_check_constraint :tracking_events,
                                                  "inventory_present IS TRUE", name: "importer_test_inventory_required"
    rows = Array.new(batch_size) { row } + [row(inventory: "False")]

    assert_no_difference "TrackingEvent.count" do
      error = assert_raises(ActiveRecord::StatementInvalid) { import(rows) }
      assert_instance_of PG::CheckViolation, error.cause
    end
  end

  test "reports cumulative staged progress across full and partial batches" do
    updates = []
    rows = Array.new(batch_size * 2) { row } + [row]
    result = import(rows) { |counts| updates << counts }

    assert_equal [
      { processed: batch_size, inserted: batch_size },
      { processed: batch_size * 2, inserted: batch_size * 2 },
      { processed: batch_size * 2 + 1, inserted: batch_size * 2 + 1 }
    ], updates
    assert_equal({ processed: batch_size * 2 + 1, inserted: batch_size * 2 + 1 }, result)
  end

  test "empty import returns zero totals without batch updates" do
    updates = []
    result = import([]) { |counts| updates << counts }

    assert_empty updates
    assert_equal({ processed: 0, inserted: 0 }, result)
  end

  test "CSV inserts explicitly use inventory presence regardless of the database default" do
    TrackingEvent.connection.execute("ALTER TABLE tracking_events ALTER COLUMN event_type SET DEFAULT 'price_tracker'")
    import([row])

    assert_equal ["inventory_presence"], TrackingEvent.pluck(:event_type)
  end

  test "quantity CSV values take precedence over legacy presence" do
    Tempfile.create(["quantity-import", ".csv"]) do |file|
      file.write(CSV.generate_line(["Address", "Product Name", "Date", "Inventory Present", "Quantity"]))
      [15, 0, -3].each do |quantity|
        file.write(CSV.generate_line(row(inventory: "True") + [quantity]))
      end
      file.flush
      TrackingEvents::CsvImporter.new(file.path).call
      assert_equal [15, 0, -3], TrackingEvent.order(:id).map { |event| event.value["quantity"] }
      assert_equal [true, false, false], TrackingEvent.order(:id).map(&:in_stock?)
    end
  end

  test "malformed explicit quantity rolls back instead of falling back to presence" do
    Tempfile.create(["quantity-import", ".csv"]) do |file|
      file.write(CSV.generate_line(["Address", "Product Name", "Date", "Inventory Present", "Quantity"]))
      file.write(CSV.generate_line(row + ["1.5"]))
      file.flush
      assert_no_difference "TrackingEvent.count" do
        error = assert_raises(TrackingEvents::CsvImporter::InvalidRow) { TrackingEvents::CsvImporter.new(file.path).call }
        assert_equal 2, error.record_number
        assert_includes error.message, "Quantity must be a whole number"
      end
    end
  end

  test "two or more products with the same name reject the import" do
    [2, 3].each do |count|
      name = "Ambiguous name #{count}"
      count.times do |index|
        brand = Brand.create!(name: "Ambiguous brand #{count}-#{index}")
        Product.create!(name: name, brand: brand)
      end

      assert_no_difference "TrackingEvent.count" do
        error = assert_raises(TrackingEvents::CsvImporter::InvalidRow) do
          import([row, row(product: name)])
        end
        assert_equal 3, error.record_number
        assert_includes error.message, name
        assert_includes error.message, "matches #{count} products"
      end
    end
  end

  test "ambiguous product in a later batch rolls back earlier inserts" do
    other_brand = Brand.create!(name: "Other brand")
    Product.create!(name: @product.name, brand: other_brand)
    unique_product = Product.create!(name: "Unambiguous product", brand: @brand)
    existing = TrackingEvent.create!(store: @store, product: unique_product, value: { quantity: 7 })
    rows = Array.new(batch_size) { row(product: unique_product.name) } + [row]

    assert_no_difference "TrackingEvent.count" do
      error = assert_raises(TrackingEvents::CsvImporter::InvalidRow) { import(rows) }
      assert_equal batch_size + 2, error.record_number
      assert_includes error.message, "matches 2 products"
    end
    assert_equal [existing.id], TrackingEvent.pluck(:id)
  end

  test "duplicate product names not referenced by the CSV do not block an import" do
    other_brand = Brand.create!(name: "Unrelated brand")
    [@brand, other_brand].each { |brand| Product.create!(name: "Unrelated duplicate", brand: brand) }
    assert_difference("TrackingEvent.count", 1) { import([row]) }
    assert_equal @product.id, TrackingEvent.last.product_id
  end

  private

  def batch_size
    TrackingEvents::CsvImporter::BATCH_SIZE
  end

  def distinct_rows(count)
    stores = Array.new(count) { |i| Store.create!(address: "#{i} Test Street, Suite \"A\"") }
    products = Array.new(count) { |i| Product.create!(name: "Test product #{i}, size \"L\"", brand: @brand) }
    expected = {}
    rows = Array.new(count) do |i|
      # Product IDs and CSV order intentionally differ from store creation order.
      store = stores[i]
      product = products[count - 1 - i]
      date = Date.new(2025, 1, 1) + i
      inventory = i.even?
      expected[date] = [store.id, product.id, inventory]
      row(address: store.address, product: product.name, date: date.iso8601, inventory: inventory ? "True" : "False")
    end
    [rows.shuffle(random: Random.new(42)), expected]
  end

  def assert_import_matches(rows, expected)
    assert_difference "TrackingEvent.count", expected.length do
      import(rows)
    end

    # Match by the source date, not database row order: SQL has no implicit ordering.
    actual = TrackingEvent.all.index_by { |event| event.event_time.to_date }
    assert_equal expected.keys.sort, actual.keys.sort
    expected.each do |date, values|
      event = actual.fetch(date)
      assert_equal values, [event.store_id, event.product_id, event.inventory_present], "Incorrect CSV mapping for #{date}"
      assert_equal "inventory_presence", event.event_type, "Incorrect event type for #{date}"
      assert_equal({ "quantity" => (values.last ? 1 : 0) }, event.value, "Incorrect JSON value for #{date}")
      assert event.created_at.present?, "Missing created_at for #{date}"
      assert event.updated_at.present?, "Missing updated_at for #{date}"
    end
  end

  def row(address: @store.address, product: @product.name, date: "2025-01-02", inventory: "True")
    [address, product, date, inventory]
  end

  def import(rows, &progress)
    Tempfile.create(["tracking-events-import-test", ".csv"]) do |file|
      file.write(CSV.generate_line(["Address", "Product Name", "Date", "Inventory Present"]))
      rows.each { |values| file.write(CSV.generate_line(values)) }
      file.flush
      result = TrackingEvents::CsvImporter.new(file.path).call(&progress)
      perform_enqueued_jobs(only: Alerts::ReconcileJob)
      result
    end
  end
end
