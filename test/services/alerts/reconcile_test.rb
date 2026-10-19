require "test_helper"

class Alerts::ReconcileTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @brand = Brand.create!(name: "Alert brand")
    @product = Product.create!(name: "Ale", brand: @brand)
    @store = Store.create!(address: "Alert shop")
    @time = Time.utc(2026, 1, 1)
  end

  test "each adjacent empty pair alerts the product brand and ignores price checks" do
    first = inventory(0, 0)
    TrackingEvent.create!(store: @store, product: @product, event_type: :price_tracker,
                          event_time: @time + 1.minute, value: { amount: 9, currency: "USD" })
    second = inventory(-1, 2)
    third = inventory(0, 3)
    assert_equal [[first.id, second.id], [second.id, third.id]], Alert.order(:observed_at).pluck(:previous_event_id, :triggering_event_id)
    assert_equal [@brand.id], Alert.distinct.pluck(:brand_id)
    ids = Alert.order(:id).pluck(:id)
    Alerts::Reconcile.call
    assert_equal ids, Alert.order(:id).pluck(:id)
  end

  test "positive and undated inventory do not qualify" do
    inventory(0, 0)
    inventory(2, 1)
    inventory(0, 2)
    TrackingEvent.create!(store: @store, product: @product, value: { quantity: 0 })
    assert_equal 0, Alert.count
  end

  test "late positive observation removes a previously adjacent pair" do
    inventory(0, 0)
    inventory(0, 2)
    assert_equal 1, Alert.count
    inventory(1, 1)
    assert_equal 0, Alert.count
  end

  test "late empty observation updates adjacency and equal times use id order" do
    first = inventory(0, 0)
    last = inventory(0, 2)
    middle = inventory(0, 1)
    assert_equal middle.id, Alert.find_by!(triggering_event: last).previous_event_id
    assert_equal first.id, Alert.find_by!(triggering_event: middle).previous_event_id
    tied = inventory(0, 2)
    assert_equal last.id, Alert.find_by!(triggering_event: tied).previous_event_id
  end

  test "pairs cannot span different stores or products" do
    inventory(0, 0)
    other_store = Store.create!(address: "Other shop")
    other_product = Product.create!(name: "Other ale", brand: Brand.create!(name: "Other brand"))
    TrackingEvent.create!(store: other_store, product: @product, event_time: @time, value: { quantity: 0 })
    TrackingEvent.create!(store: @store, product: other_product, event_time: @time, value: { quantity: 0 })
    assert_equal 0, Alert.count
  end

  test "observation and alert creation roll back together" do
    inventory(0, 0)
    assert_no_difference ["Alert.count", "TrackingEvent.count"] do
      TrackingEvent.transaction do
        inventory(0, 1)
        assert_equal 1, Alert.count
        raise ActiveRecord::Rollback
      end
    end
  end

  test "bulk observations become alerts on reconciliation" do
    TrackingEvent.insert_all!([0, 1].map { |minute|
      { store_id: @store.id, product_id: @product.id,
        event_type: "inventory_presence", event_time: @time + minute.minutes, value: { quantity: 0 } }
    })
    assert_equal 0, Alert.count
    Alerts::Reconcile.call
    assert_equal 1, Alert.count
  end

  test "historical tracking records cannot create alerts after a clean start" do
    old_first = inventory(0, 0)
    old_second = inventory(0, 1)
    TrackingEvent.where(id: [old_first.id, old_second.id]).update_all(alert_eligible: false)
    Alert.delete_all

    Alerts::Reconcile.call
    assert_equal 0, Alert.count
    first_new = inventory(0, 2)
    assert_equal 0, Alert.count
    second_new = inventory(0, 3)
    assert_equal [[first_new.id, second_new.id]], Alert.pluck(:previous_event_id, :triggering_event_id)
    Alerts::Reconcile.call
    assert_equal 1, Alert.count
  end

  test "price changes create unread alerts independently of inventory and contact preferences" do
    price(10, 0)
    assert_equal 0, Alert.count
    same = price(10, 1)
    inventory(0, 0)
    inventory(0, 1)
    changed = price(12, 2)
    cheaper = price(8, 3)
    price(8, 4)
    price(9, 5, currency: "EUR")
    price(10, nil)
    alerts = Alert.where(alert_type: "alert_price_change").order(:observed_at)
    assert_equal [[same.id, changed.id], [changed.id, cheaper.id]], alerts.pluck(:previous_event_id, :triggering_event_id)
    assert alerts.all? { |alert| alert.seen_at.nil? && alert.brand_id == @brand.id }
    assert_equal 1, Alert.where(alert_type: "alert_no_inventory").count
    alert = alerts.first
    alert.mark_seen!
    assert_no_difference "Alert.count" do
      2.times { Alerts::Reconcile.call }
    end
    assert_not_nil alert.reload.seen_at
    assert_equal same.id, alert.previous_event_id
  end

  test "historical prices provide a baseline but never trigger a backfill" do
    price(10, 0, price_alert_eligible: false)
    baseline = price(12, 1, price_alert_eligible: false)
    Alerts::Reconcile.call
    assert_equal 0, Alert.count
    new_event = price(15, 2)
    assert_equal [[baseline.id, new_event.id]], Alert.pluck(:previous_event_id, :triggering_event_id)
  end

  test "late price observations reconcile adjacency and tied times use id" do
    first = price(10, 0)
    last = price(12, 2)
    middle = price(12, 1)
    assert_not Alert.exists?(triggering_event: last)
    assert_equal first.id, Alert.find_by!(triggering_event: middle).previous_event_id
    tied = price(8, 2)
    assert_equal last.id, Alert.find_by!(triggering_event: tied).previous_event_id
  end

  test "bulk price writes are reconciled without model callbacks and invalid alert types are rejected" do
    TrackingEvent.insert_all!([10, 12].each_with_index.map { |amount, minute|
      { store_id: @store.id, product_id: @product.id, event_type: "price_tracker",
        event_time: @time + minute.minutes, value: { amount: amount, currency: "USD" } }
    })
    assert_equal 0, Alert.count
    Alerts::Reconcile.call
    assert_equal "alert_price_change", Alert.sole.alert_type
    assert_not Alert.sole.update(alert_type: "unknown")
    assert_raises(ActiveRecord::StatementInvalid) do
      Alert.transaction(requires_new: true) { Alert.sole.update_columns(alert_type: "unknown") }
    end
  end

  test "price comparisons stay within store and product and exclude ineligible observations" do
    price(10, 0, alert_eligible: false)
    baseline = price(12, 1)
    other_store = Store.create!(address: "Other price shop")
    other_product = Product.create!(name: "Other price product", brand: @brand)
    perform_enqueued_jobs(only: Alerts::ReconcileJob) do
      [[other_store, @product], [@store, other_product]].each do |store, product|
        TrackingEvent.create!(store: store, product: product, event_type: :price_tracker,
                              event_time: @time + 2.minutes, value: { amount: 20, currency: "USD" })
      end
    end
    assert_equal 0, Alert.count
    changed = price(14, 3)
    assert_equal [[baseline.id, changed.id]], Alert.pluck(:previous_event_id, :triggering_event_id)
  end

  test "price inbox alerts and observations roll back together" do
    price(10, 0)
    assert_no_difference ["TrackingEvent.count", "Alert.count"] do
      TrackingEvent.transaction do
        price(12, 1)
        assert_equal 1, Alert.count
        raise ActiveRecord::Rollback
      end
    end
  end

  private

  def price(amount, minute, currency: "USD", **attributes)
    event = nil
    perform_enqueued_jobs(only: Alerts::ReconcileJob) do
      event = TrackingEvent.create!(store: @store, product: @product, event_type: :price_tracker,
                                    event_time: minute && @time + minute.minutes,
                                    value: { amount: amount, currency: currency }, **attributes)
    end
    event
  end

  def inventory(quantity, minute)
    event = nil
    perform_enqueued_jobs(only: Alerts::ReconcileJob) do
      event = TrackingEvent.create!(store: @store, product: @product,
                                    event_time: @time + minute.minutes, value: { quantity: quantity })
    end
    event
  end
end
