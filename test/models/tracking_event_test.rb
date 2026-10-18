require "test_helper"

class TrackingEventTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @store = Store.create!(address: "Enum test store")
    brand = Brand.create!(name: "Enum test brand")
    @product = Product.create!(name: "Enum test product", brand: brand)
  end

  test "existing default categorizes new events as inventory presence" do
    event = TrackingEvent.create!(store: @store, product: @product, value: { present: false })

    assert_equal "inventory_presence", event.reload.event_type
    assert event.inventory_presence?
    assert_instance_of TrackingEvent, event
  end

  test "price tracker events persist and load without Rails inheritance" do
    event = TrackingEvent.create!(store: @store, product: @product, event_type: :price_tracker, value: { amount: 0, currency: "USD" })

    assert event.reload.price_tracker?
    assert_instance_of TrackingEvent, TrackingEvent.find(event.id)
    assert_includes TrackingEvent.price_tracker, event
    refute_includes TrackingEvent.inventory_presence, event
  end

  test "unknown types are rejected by the model" do
    assert_raises(ArgumentError) { TrackingEvent.new(event_type: "unknown") }
  end

  test "database rejects unknown and null event types" do
    event = TrackingEvent.create!(store: @store, product: @product, value: { present: false })
    { "'unknown'" => PG::InvalidTextRepresentation, "NULL" => PG::NotNullViolation }.each do |value, error_class|
      error = assert_raises(ActiveRecord::StatementInvalid) do
        TrackingEvent.transaction(requires_new: true) do
          TrackingEvent.connection.execute("UPDATE tracking_events SET event_type = #{value} WHERE id = #{event.id}")
        end
      end
      assert_instance_of error_class, error.cause
    end
    assert event.reload.inventory_presence?
  end

  test "inventory accepts both boolean observations" do
    [true, false].each do |present|
      event = TrackingEvent.create!(store: @store, product: @product, value: { present: present })
      assert_equal({ "present" => present }, event.reload.value)
    end
  end

  test "inventory rejects missing null and nonboolean observations in Rails and bulk inserts" do
    [nil, [], {}, { present: nil }, { present: "false" }, { present: 0 }].each do |payload|
      assert_invalid_payload(:inventory_presence, payload)
    end
  end

  test "prices accept zero and positive numeric amounts" do
    [0, 12, 12.5].each do |amount|
      event = TrackingEvent.create!(store: @store, product: @product,
        event_type: :price_tracker, value: { amount: amount, currency: "USD" })
      assert_equal amount, event.reload.value["amount"]
    end
  end

  test "prices require a nonnegative number and uppercase currency code in Rails and bulk inserts" do
    [nil, [], {}, { amount: 0 }, { currency: "USD" }].each do |payload|
      assert_invalid_payload(:price_tracker, payload)
    end
    [nil, -1, -0.01, Float::NAN, Float::INFINITY, "12.5", "NaN", "Infinity", true, [], {}].each do |amount|
      assert_invalid_payload(:price_tracker, { amount: amount, currency: "USD" })
    end
    [nil, "", "usd", "US", "USDD", "123", "USD\n", 123, true].each do |currency|
      assert_invalid_payload(:price_tracker, { amount: 0, currency: currency })
    end
  end

  test "bulk inserts accept false and zero" do
    TrackingEvent.insert_all!([
      { store_id: @store.id, product_id: @product.id, event_type: "inventory_presence", value: { present: false } },
      { store_id: @store.id, product_id: @product.id, event_type: "price_tracker", value: { amount: 0, currency: "USD" } }
    ])
    assert_equal false, TrackingEvent.inventory_presence.last.value["present"]
    assert_equal 0, TrackingEvent.price_tracker.last.value["amount"]
  end

  test "payload must remain valid when the event category changes" do
    event = TrackingEvent.create!(store: @store, product: @product, value: { present: false })
    refute event.update(event_type: :price_tracker)
    assert_raises(ActiveRecord::StatementInvalid) do
      TrackingEvent.transaction(requires_new: true) { event.update_columns(event_type: "price_tracker") }
    end
  end

  private

  def assert_invalid_payload(event_type, payload)
    attributes = { store_id: @store.id, product_id: @product.id, event_type: event_type, value: payload }
    event = TrackingEvent.new(attributes)
    refute event.valid?, "Accepted invalid #{event_type} payload: #{payload.inspect}"
    assert event.errors[:value].any?
    error = assert_raises(ActiveRecord::StatementInvalid) do
      TrackingEvent.transaction(requires_new: true) { TrackingEvent.insert_all!([attributes]) }
    end
    assert_includes [PG::CheckViolation, PG::NotNullViolation], error.cause.class
  end
end
