require "test_helper"

class Alerts::TransactionalQueueTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  test "durable job insertion shares the tracking transaction and rolls back with it" do
    original = Alerts::ReconcileJob.queue_adapter
    Alerts::ReconcileJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    brand = Brand.create!(name: "Queue test brand")
    product = Product.create!(name: "Queue test product", brand: brand)
    store = Store.create!(address: "Queue test store")
    before = GoodJob::Job.count
    assert_no_difference ["TrackingEvent.count", "GoodJob::Job.count"] do
      TrackingEvent.transaction(requires_new: true) do
        TrackingEvent.create!(store: store, product: product, event_time: Time.current, value: { quantity: 0 })
        assert_equal before + 1, GoodJob::Job.count
        assert_equal "Alerts::ReconcileJob", GoodJob::Job.order(:created_at).last.job_class
        raise ActiveRecord::Rollback
      end
    end
  ensure
    Alerts::ReconcileJob.queue_adapter = original
  end
end
