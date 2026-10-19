require "test_helper"
require "tempfile"

class TrackingEvents::CsvImporterTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @store = Store.create!(address: "Importer test address")
    @brand = Brand.create!(name: "Importer test brand")
    @product = Product.create!(name: "Importer test product", brand: @brand)
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

  test "missing references stop each batch while preserving previously collected events" do
    rows, expected = distinct_rows(batch_size + 2)
    retained_dates = rows.first(batch_size - 1).map { |values| Date.parse(values[2]) }
    expected = expected.slice(*retained_dates)
    # A missing reference ends each batch, including the next batch's first row.
    rows.insert(batch_size - 1, row(address: "Missing", date: "invalid"))
    rows.insert(batch_size, row(product: "Missing", date: "invalid"))

    assert_import_matches(rows, expected)
  end

  test "empty files and batches with no matching references create no events" do
    assert_no_difference "TrackingEvent.count" do
      import([])
      import(Array.new(batch_size) { row(product: "Missing") })
    end
  end

  test "an invalid date fails before inserting the current batch" do
    assert_no_difference "TrackingEvent.count" do
      assert_raises(Date::Error) { import([row, row(date: "invalid")]) }
    end
  end

  test "a later invalid date rolls back earlier batches and preserves existing events" do
    existing = TrackingEvent.create!(store: @store, product: @product, event_time: Date.new(2024, 1, 1), inventory_present: true, value: { quantity: 1 })
    rows = Array.new(batch_size) { row } + [row(date: "invalid")]

    assert_no_difference "TrackingEvent.count" do
      assert_raises(Date::Error) { import(rows) }
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

  test "reports cumulative progress including skipped batches and final partial batches" do
    updates = []
    rows = Array.new(batch_size) { row } + Array.new(batch_size) { row(product: "Missing") } + [row]
    result = import(rows) { |counts| updates << counts }

    assert_equal [
      { processed: batch_size, inserted: batch_size },
      { processed: batch_size * 2, inserted: batch_size },
      { processed: batch_size * 2 + 1, inserted: batch_size + 1 }
    ], updates
    assert_equal({ processed: batch_size * 2 + 1, inserted: batch_size + 1 }, result)
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
        assert_raises(ArgumentError) { TrackingEvents::CsvImporter.new(file.path).call }
      end
    end
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
      TrackingEvents::CsvImporter.new(file.path).call(&progress)
    end
  end
end
