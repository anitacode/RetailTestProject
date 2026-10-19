require "test_helper"

class Api::QueuedJobsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @brand = Brand.create!(name: "Queue brand")
    @other = Brand.create!(name: "Other queue brand")
    @product = Product.create!(brand: @brand, name: "Product")
    @other_product = Product.create!(brand: @other, name: "Other product")
  end

  test "brand sees only attributable jobs with safe status fields" do
    own = job(@product.id)
    job(@other_product.id)
    job(nil)
    GoodJob::Job.create!(job_class: "UnknownJob", serialized_params: { arguments: [] })
    get "/api/queued_jobs"
    assert_response :unauthorized
    sign_in
    get "/api/queued_jobs"
    assert_response :success
    assert_equal [own.id], response.parsed_body["jobs"].map { |item| item["id"] }
    item = response.parsed_body["jobs"].first
    assert_equal "queued", item["status"]
    assert_equal %w[attempts created_at finished_at id job_class queue scheduled_at status], item.keys.sort
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "status distinguishes scheduled running retries completed and failures" do
    sign_in
    states = {
      "scheduled" => { scheduled_at: 1.hour.from_now },
      "running" => { locked_by_id: SecureRandom.uuid },
      "retrying" => { error: "private exception", scheduled_at: 1.minute.from_now },
      "completed" => { finished_at: Time.current },
      "failed" => { finished_at: Time.current, error: "private exception" }
    }
    ids = states.to_h { |state, attributes| [job(@product.id, **attributes).id, state] }
    get "/api/queued_jobs"
    assert_response :success
    response.parsed_body["jobs"].each { |item| assert_equal ids[item["id"]], item["status"] }
    assert_not_includes response.body, "private exception"
  end

  test "notification job source ownership controls visibility" do
    store = Store.create!(address: "Shop")
    own_event = TrackingEvent.create!(product: @product, store: store, event_type: :price_tracker, value: { amount: 1, currency: "USD" }, event_time: Time.current)
    other_event = TrackingEvent.create!(product: @other_product, store: store, event_type: :price_tracker, value: { amount: 1, currency: "USD" }, event_time: Time.current)
    own = GoodJob::Job.create!(job_class: "Notifications::DispatchJob", serialized_params: { arguments: ["alert_price_change", own_event.id] })
    GoodJob::Job.create!(job_class: "Notifications::DeliverJob", serialized_params: { arguments: ["alert_price_change", other_event.id, 1, "email"] })
    sign_in
    get "/api/queued_jobs"
    assert_equal [own.id], response.parsed_body["jobs"].map { |item| item["id"] }
  end

  test "jobs are paginated with validated page numbers" do
    21.times { job(@product.id) }
    sign_in
    get "/api/queued_jobs"
    assert_equal 20, response.parsed_body["jobs"].length
    assert_equal 21, response.parsed_body.dig("pagination", "total")
    get "/api/queued_jobs", params: { page: 2 }
    assert_equal 1, response.parsed_body["jobs"].length
    get "/api/queued_jobs", params: { page: "1x" }
    assert_response :unprocessable_entity
  end

  test "retry requeues the failed job once without running it in the request" do
    failed = failed_job(@product.id)
    sign_in
    with_good_job do
      assert_no_difference "GoodJob::Job.count" do
        post "/api/queued_jobs/#{failed.id}/retry"
        assert_response :accepted
        assert_equal "accepted", response.parsed_body["status"]
      end
      assert_nil failed.reload.finished_at
      assert failed.scheduled_at <= Time.current
      post "/api/queued_jobs/#{failed.id}/retry"
      assert_response :conflict
    end
  end

  test "retry rejects anonymous cross-brand missing global and nonfailed jobs" do
    own = failed_job(@product.id)
    post "/api/queued_jobs/#{own.id}/retry"
    assert_response :unauthorized
    sign_in
    [failed_job(@other_product.id), failed_job(nil)].each do |hidden|
      post "/api/queued_jobs/#{hidden.id}/retry"
      assert_response :not_found
      assert_not_nil hidden.reload.finished_at
    end
    post "/api/queued_jobs/#{SecureRandom.uuid}/retry"
    assert_response :not_found
    [{}, { finished_at: Time.current }, { locked_by_id: SecureRandom.uuid }, { error: "retry pending" }].each do |state|
      other = job(@product.id, **state)
      post "/api/queued_jobs/#{other.id}/retry"
      assert_response :conflict
    end
  end

  test "retry enforces csrf" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/api/session"
    token = response.parsed_body["csrf_token"]
    post "/api/session", params: { name: @brand.name }, headers: { "X-CSRF-Token" => token }, as: :json
    token = response.parsed_body["csrf_token"]
    failed = failed_job(@product.id)
    post "/api/queued_jobs/#{failed.id}/retry"
    assert_response :unprocessable_entity
    assert_not_nil failed.reload.finished_at
    with_good_job do
      post "/api/queued_jobs/#{failed.id}/retry", headers: { "X-CSRF-Token" => token }, as: :json
      assert_response :accepted
    end
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  private

  def failed_job(product_id)
    active_job = Alerts::ReconcileJob.new(store_id: 1, product_id: product_id)
    GoodJob::Job.create!(id: active_job.job_id, active_job_id: active_job.job_id, job_class: active_job.class.name, queue_name: "alerts",
                         serialized_params: active_job.serialize, finished_at: Time.current,
                         error: "StandardError: simulated failure")
  end

  def with_good_job
    original = Alerts::ReconcileJob._queue_adapter
    original_test_adapter = Alerts::ReconcileJob._test_adapter
    Alerts::ReconcileJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    Alerts::ReconcileJob.disable_test_adapter
    yield
  ensure
    Alerts::ReconcileJob.queue_adapter = original
    Alerts::ReconcileJob.enable_test_adapter(original_test_adapter)
  end

  def sign_in
    post "/api/session", params: { name: @brand.name }, as: :json
    assert_response :success
  end

  def job(product_id, **attributes)
    GoodJob::Job.create!({ job_class: "Alerts::ReconcileJob", queue_name: "alerts",
                           serialized_params: { arguments: [{ product_id: product_id, store_id: 1 }] } }.merge(attributes))
  end
end
