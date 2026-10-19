require "test_helper"

class Notifications::ContactDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @brand = Brand.create!(name: "Notification brand")
    @store = Store.create!(address: "Notification shop")
    @product = Product.create!(brand: @brand, name: "Tea")
  end

  test "all opted-in contacts receive every available channel and other brands receive nothing" do
    both = contact(email: "both@example.com", phone: "+12025550123")
    email_only = contact(email: "email@example.com")
    contact(email: "off@example.com", enabled: false)
    other = Brand.create!(name: "Other brand")
    other.contacts.create!(name: "Other recipient", email: "other@example.com", setup: both.setup)
    capture_io do
      perform_enqueued_jobs do
        inventory(0)
        inventory(1)
      end
    end
    assert_equal [[both.id, "email"], [both.id, "sms"], [email_only.id, "email"]],
                 NotificationDelivery.order(:contact_id, :channel).pluck(:contact_id, :channel)
  end

  test "delivery rechecks preferences destinations and brand after dispatch" do
    recipient = contact(email: "old@example.com")
    inventory(0)
    inventory(1)
    perform_enqueued_jobs(only: Alerts::ReconcileJob)
    perform_enqueued_jobs(only: Notifications::DispatchJob)
    recipient.update!(setup: { alert_no_inventory: false, alert_price_change: false })
    perform_enqueued_jobs(only: Notifications::DeliverJob)
    assert_equal 0, NotificationDelivery.count
    recipient.update!(setup: { alert_no_inventory: true, alert_price_change: false }, email: "new@example.com")
    capture_io { Notifications::DeliverJob.perform_now("alert_no_inventory", Alert.sole.id, recipient.id, "email") }
    assert_equal "new@example.com", NotificationDelivery.sole.destination
    recipient.update!(brand: Brand.create!(name: "Moved brand"))
    assert_no_difference "NotificationDelivery.count" do
      Notifications::DeliverJob.perform_now("alert_no_inventory", Alert.sole.id, recipient.id, "sms")
    end
  end

  test "price changes notify subscribers once but baselines same prices and currency changes do not" do
    recipient = contact(email: "prices@example.com", enabled: false)
    recipient.update!(setup: { alert_no_inventory: false, alert_price_change: true })
    contact(email: "inventory@example.com")
    capture_io do
      perform_enqueued_jobs do
        price(0, 10)
        price(1, 10)
        @changed = price(2, 12)
        price(3, 15, currency: "EUR")
      end
    end
    assert_equal 1, NotificationDelivery.count
    delivery = NotificationDelivery.sole
    assert_equal @changed.id, Alert.find_by!(alert_type: "alert_price_change").triggering_event_id
    assert_equal @changed.id, delivery.tracking_event_id
    assert_equal "alert_price_change", delivery.kind
    assert_includes delivery.body, "10 to 12 USD"
    capture_io do
      perform_enqueued_jobs do
        2.times { Notifications::DispatchJob.perform_now("alert_price_change", @changed.id) }
      end
    end
    assert_equal 1, NotificationDelivery.count
  end

  test "missing sources and deleted contacts are skipped" do
    assert_no_enqueued_jobs { Notifications::DispatchJob.perform_now("alert_no_inventory", -1) }
    assert_no_difference "NotificationDelivery.count" do
      Notifications::DeliverJob.perform_now("alert_no_inventory", -1, -1, "email")
    end
  end

  private

  def contact(email: nil, phone: nil, enabled: true)
    @brand.contacts.create!(name: "Recipient", email: email, phone: phone,
                            setup: { alert_no_inventory: enabled, alert_price_change: false })
  end

  def inventory(minute)
    TrackingEvent.create!(store: @store, product: @product, event_time: Time.utc(2026, 10, 19) + minute.minutes, value: { quantity: 0 })
  end

  def price(minute, amount, currency: "USD")
    TrackingEvent.create!(store: @store, product: @product, event_type: :price_tracker,
                          event_time: Time.utc(2026, 10, 19) + minute.minutes, value: { amount: amount, currency: currency })
  end
end
