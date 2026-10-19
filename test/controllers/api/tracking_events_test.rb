require "test_helper"

class Api::TrackingEventsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @brand = Brand.create!(name: "Events brand")
    @other = Brand.create!(name: "Other events brand")
    @product = Product.create!(brand: @brand, name: "Tea")
    @other_product = Product.create!(brand: @other, name: "Other tea")
    @store = Store.create!(address: "Shared shop")
  end

  test "only current brand product observations are visible even in a shared store" do
    own = event(@product)
    event(@other_product)
    foreign_store = Store.create!(address: "Other brand only shop")
    event(@other_product, store: foreign_store)
    get "/api/tracking_events"
    assert_response :unauthorized
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/tracking_events", params: { brand_id: @other.id }
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    assert_equal [own.id], body["tracking_events"].map { |item| item["id"] }
    item = body["tracking_events"].first
    assert_equal %w[event_time event_type id product store value], item.keys.sort
    assert_equal @store.id, item.dig("store", "id")
    assert_equal({ "quantity" => 0 }, item["value"])
    assert_equal 1, body.dig("pagination", "total")
    assert TrackingEventPolicy::Scope.new(nil, TrackingEvent).resolve.empty?
    post "/api/session", params: { name: @other.name }, as: :json
    get "/api/tracking_events"
    assert_equal 2, response.parsed_body.dig("pagination", "total")
    assert_not_includes response.parsed_body["tracking_events"].map { |item| item["id"] }, own.id
  end

  test "pagination orders by observation time then id with undated events last" do
    undated = event(@product, event_time: nil)
    time = Time.utc(2026, 10, 19)
    dated = 21.times.map { event(@product, event_time: time) }
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/tracking_events"
    assert_equal dated.reverse.first(20).map(&:id), response.parsed_body["tracking_events"].map { |item| item["id"] }
    assert_equal({ "page" => 1, "per_page" => 20, "total" => 22, "pages" => 2 }, response.parsed_body["pagination"])
    get "/api/tracking_events", params: { page: 2 }
    assert_equal [dated.first.id, undated.id], response.parsed_body["tracking_events"].map { |item| item["id"] }
    assert_nil response.parsed_body["tracking_events"].last["event_time"]
    get "/api/tracking_events", params: { page: 3 }
    assert_empty response.parsed_body["tracking_events"]
    ["0", "-1", "1x", "1000000"].each do |page|
      get "/api/tracking_events", params: { page: page }
      assert_response :unprocessable_entity
    end
  end

  test "ascending observation order stays scoped and paginated with undated events last" do
    undated = event(@product, event_time: nil)
    newest = event(@product, event_time: Time.utc(2026, 10, 20))
    older = 20.times.map { event(@product, event_time: Time.utc(2026, 10, 19)) }
    event(@other_product, event_time: Time.utc(2026, 10, 18))
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/tracking_events", params: { order: "asc" }
    assert_response :success
    assert_equal older.map(&:id), response.parsed_body["tracking_events"].map { |item| item["id"] }
    get "/api/tracking_events", params: { order: "asc", page: 2 }
    assert_equal [newest.id, undated.id], response.parsed_body["tracking_events"].map { |item| item["id"] }
    ["invalid", "asc; DROP TABLE tracking_events"].each do |order|
      get "/api/tracking_events", params: { order: order }
      assert_response :unprocessable_entity
    end
    get "/api/tracking_events", params: { order: "desc" }
    assert_equal newest.id, response.parsed_body["tracking_events"].first["id"]
  end

  test "price observations expose amount and currency without internal fields" do
    event(@product, event_type: :price_tracker, value: { amount: 11.99, currency: "USD", private_note: "not public" })
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/tracking_events"
    assert_equal({ "amount" => 11.99, "currency" => "USD" }, response.parsed_body["tracking_events"].sole["value"])
    assert_not_includes response.body, "not public"
  end

  private

  def event(product, **attributes)
    TrackingEvent.create!({ product: product, store: @store, event_time: Time.current,
                            value: { quantity: 0 }, alert_eligible: false }.merge(attributes))
  end
end
