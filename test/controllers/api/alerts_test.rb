require "test_helper"

class Api::AlertsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @brand = Brand.create!(name: "Demo brand")
    @other_brand = Brand.create!(name: "Other brand")
    store = Store.create!(address: "Demo shop")
    [@brand, @other_brand].each do |brand|
      product = Product.create!(name: "Ale", brand: brand)
      perform_enqueued_jobs(only: Alerts::ReconcileJob) do
        3.times { |i| TrackingEvent.create!(store: store, product: product, event_time: Time.utc(2026, 1, 1) + i.minutes, value: { quantity: 0 }) }
      end
    end
  end

  test "anonymous requests require sign in" do
    get "/api/alerts"
    assert_response :unauthorized
    get "/api/alerts/#{Alert.first.id}"
    assert_response :unauthorized
    get "/api/session"
    assert_response :success
    assert_nil response.parsed_body["brand"]
    assert response.parsed_body["csrf_token"].present?
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "name login is normalized and limits lists and details to its brand" do
    post "/api/session", params: { name: "  DEMO BRAND  " }, as: :json
    assert_response :success
    assert_equal @brand.id, response.parsed_body.dig("brand", "id")
    get "/api/alerts"
    assert_response :success
    body = response.parsed_body
    assert_equal 2, body.dig("pagination", "total")
    assert_equal ["alert_no_inventory"], body["alerts"].map { |a| a["alert_type"] }.uniq
    assert_equal Alert.where(brand: @brand).newest_first.pluck(:id), body["alerts"].map { |a| a["id"] }
    get "/api/alerts/#{Alert.where(brand: @brand).first.id}"
    assert_response :success
    assert_equal "alert_no_inventory", response.parsed_body.dig("alert", "alert_type")
    assert_equal [0, 0], response.parsed_body["alert"]["observations"].map { |o| o["quantity"] }
    get "/api/alerts/#{Alert.where(brand: @other_brand).first.id}"
    assert_response :not_found
    get "/api/alerts/999999999"
    assert_response :not_found
    delete "/api/session"
    assert_response :success
    get "/api/alerts"
    assert_response :unauthorized
  end

  test "price alerts expose prices and retain brand isolation and seen tracking" do
    product = Product.find_by!(brand: @brand)
    store = Store.first
    perform_enqueued_jobs(only: Alerts::ReconcileJob) do
      [10, 12].each_with_index do |amount, i|
        TrackingEvent.create!(store: store, product: product, event_type: :price_tracker,
                              event_time: Time.utc(2026, 2, 1) + i.minutes, value: { amount: amount, currency: "USD" })
      end
    end
    alert = Alert.find_by!(alert_type: "alert_price_change")
    get "/api/alerts/#{alert.id}"
    assert_response :unauthorized
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/alerts"
    assert_equal 3, response.parsed_body["unseen_count"]
    assert_includes response.parsed_body["alerts"].map { |a| a["alert_type"] }, "alert_price_change"
    get "/api/alerts/#{alert.id}"
    assert_response :success
    body = response.parsed_body["alert"]
    assert_equal "alert_price_change", body["alert_type"]
    assert_equal [10, 12], body["observations"].map { |o| o["amount"] }
    assert body["observations"].all? { |o| o["currency"] == "USD" && !o.key?("quantity") }
    patch "/api/alerts/#{alert.id}/seen"
    assert_response :success
    assert_not_nil alert.reload.seen_at
    post "/api/session", params: { name: @other_brand.name }, as: :json
    get "/api/alerts/#{alert.id}"
    assert_response :not_found
    patch "/api/alerts/#{alert.id}/seen"
    assert_response :not_found
  end

  test "invalid and ambiguous names fail without signing in" do
    [nil, "", [], "Unknown"].each do |name|
      post "/api/session", params: { name: name }, as: :json
      assert_response :unprocessable_entity
    end
    Brand.create!(name: @brand.name.upcase)
    post "/api/session", params: { name: @brand.name }, as: :json
    assert_response :unprocessable_entity
    get "/api/alerts"
    assert_response :unauthorized
  end

  test "pagination rejects invalid input and bounds collections" do
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/alerts", params: { page: 0 }
    assert_response :unprocessable_entity
    get "/api/alerts", params: { page: 2 }
    assert_response :success
    assert_empty response.parsed_body["alerts"]
    assert_equal 20, response.parsed_body.dig("pagination", "per_page")
  end

  test "session changes require csrf protection" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/api/session"
    token = response.parsed_body["csrf_token"]
    post "/api/session", params: { name: @brand.name }, as: :json
    assert_response :unprocessable_entity
    post "/api/session", params: { name: @brand.name }, headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :success
    delete "/api/session", as: :json
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "seen state is explicit idempotent and counted across pages" do
    post "/api/session", params: { name: @brand.name }, as: :json
    alert = Alert.where(brand: @brand).first
    get "/api/alerts/#{alert.id}"
    assert_nil response.parsed_body.dig("alert", "seen_at")
    assert_nil alert.reload.seen_at
    get "/api/alerts", params: { page: 2 }
    assert_equal 2, response.parsed_body["unseen_count"]
    assert_empty response.parsed_body["alerts"]

    patch "/api/alerts/#{alert.id}/seen", params: { seen_at: "2000-01-01", brand_id: @other_brand.id }, as: :json
    assert_response :success
    first_seen = alert.reload.seen_at
    assert first_seen.present?
    assert_equal first_seen.iso8601(6), response.parsed_body["seen_at"]
    assert_equal @brand.id, alert.brand_id
    travel 1.minute do
      patch "/api/alerts/#{alert.id}/seen", as: :json
      assert_response :success
      assert_equal first_seen, alert.reload.seen_at
    end
    get "/api/alerts"
    assert_equal 1, response.parsed_body["unseen_count"]
    assert_equal 2, response.parsed_body.dig("pagination", "total")
    assert_equal 2, response.parsed_body["alerts"].length
    assert_equal first_seen.iso8601(6), response.parsed_body["alerts"].find { |item| item["id"] == alert.id }["seen_at"]
    delete "/api/session"
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/alerts"
    assert_equal 1, response.parsed_body["unseen_count"]
    perform_enqueued_jobs(only: Alerts::ReconcileJob) do
      TrackingEvent.create!(store_id: alert.store_id, product_id: alert.product_id,
                            event_time: Time.utc(2026, 1, 1) + 3.minutes, value: { quantity: 0 })
    end
    assert_equal first_seen, alert.reload.seen_at
    get "/api/alerts"
    assert_equal 2, response.parsed_body["unseen_count"]
    assert_equal 3, response.parsed_body.dig("pagination", "total")
  end

  test "seen writes reject anonymous missing and cross brand records" do
    alert = Alert.where(brand: @other_brand).first
    patch "/api/alerts/#{alert.id}/seen", as: :json
    assert_response :unauthorized
    post "/api/session", params: { name: @brand.name }, as: :json
    patch "/api/alerts/#{alert.id}/seen", as: :json
    assert_response :not_found
    assert_nil alert.reload.seen_at
    patch "/api/alerts/999999999/seen", as: :json
    assert_response :not_found
  end

  test "seen writes require a csrf token" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/api/session"
    token = response.parsed_body["csrf_token"]
    post "/api/session", params: { name: @brand.name }, headers: { "X-CSRF-Token" => token }, as: :json
    token = response.parsed_body["csrf_token"]
    alert = Alert.where(brand: @brand).first
    patch "/api/alerts/#{alert.id}/seen", as: :json
    assert_response :unprocessable_entity
    assert_nil alert.reload.seen_at
    patch "/api/alerts/#{alert.id}/seen", headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :success
    assert alert.reload.seen_at.present?
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
