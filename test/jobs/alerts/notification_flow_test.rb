require "test_helper"
require "minitest/mock"

class Alerts::NotificationFlowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @brand = Brand.create!(name: "SMS demo brand")
    @product = Product.create!(name: "Demo ale", brand: @brand)
    @store = Store.create!(address: "Demo shop")
    @contact = @brand.contacts.create!(name: "Demo recipient", phone: "+12025550123", setup: { alert_no_inventory: true, alert_price_change: false })
  end

  test "new inventory queues calculation then a simulated SMS without blocking the write" do
    assert_enqueued_jobs 2, only: Alerts::ReconcileJob do
      2.times { |index| observation(index) }
    end
    assert_equal 0, Alert.count
    assert_equal 0, NotificationDelivery.count
    output, = capture_io do
      perform_enqueued_jobs(only: Alerts::ReconcileJob)
      perform_enqueued_jobs(only: Notifications::DispatchJob)
      perform_enqueued_jobs(only: Notifications::DeliverJob)
    end
    assert_equal 1, Alert.count
    delivery = NotificationDelivery.sole
    assert_equal @contact.phone, delivery.destination
    assert_includes delivery.body, @brand.name
    assert_includes delivery.body, @product.name
    assert_includes output, "[SMS SIMULATED]"
    assert_includes output, "no real message sent"
  end

  test "repeated reconciliation and duplicate notification jobs do not send twice" do
    2.times { |index| observation(index) }
    capture_io do
      perform_enqueued_jobs(only: Alerts::ReconcileJob)
      perform_enqueued_jobs(only: Notifications::DispatchJob)
      perform_enqueued_jobs(only: Notifications::DeliverJob)
    end
    assert_no_difference "NotificationDelivery.count" do
      output, = capture_io do
        Alerts::ReconcileJob.perform_now(store_id: @store.id, product_id: @product.id)
        2.times { Notifications::DeliverJob.perform_now("alert_no_inventory", Alert.sole.id, @contact.id, "sms") }
      end
      assert_empty output
    end
    assert_no_enqueued_jobs only: Notifications::DeliverJob
  end

  test "an alert invalidated before its notification runs is skipped" do
    observation(0)
    observation(2)
    perform_enqueued_jobs(only: Alerts::ReconcileJob)
    id = Alert.sole.id
    observation(1, quantity: 4)
    perform_enqueued_jobs(only: Alerts::ReconcileJob)
    assert_equal 0, Alert.count
    assert_no_difference "NotificationDelivery.count" do
      Notifications::DeliverJob.perform_now("alert_no_inventory", id, @contact.id, "sms")
    end
  end

  test "undated observations and historical inventory do not enqueue" do
    assert_no_enqueued_jobs do
      TrackingEvent.create!(store: @store, product: @product, value: { quantity: 0 })
      observation(0, alert_eligible: false)
    end
  end

  test "transient database errors schedule a bounded retry" do
    failing = ->(**_args) { raise ActiveRecord::Deadlocked, "test deadlock" }
    Alerts::Reconcile.stub(:call, failing) do
      assert_enqueued_with(job: Alerts::ReconcileJob) do
        Alerts::ReconcileJob.perform_now(store_id: @store.id, product_id: @product.id)
      end
      exhausted = Alerts::ReconcileJob.new(store_id: @store.id, product_id: @product.id)
      exhausted.executions = 2
      exhausted.exception_executions = { [ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout].to_s => 2 }
      assert_raises(ActiveRecord::Deadlocked) { exhausted.perform_now }
    end
  end

  private

  def observation(minute, quantity: 0, alert_eligible: true)
    TrackingEvent.create!(store: @store, product: @product,
                          event_time: Time.utc(2026, 10, 19) + minute.minutes,
                          value: { quantity: quantity }, alert_eligible: alert_eligible)
  end
end
