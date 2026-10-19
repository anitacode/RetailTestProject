require "test_helper"

class Api::ContactsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup do
    @brand = Brand.create!(name: "Contact brand")
    @other_brand = Brand.create!(name: "Another contact brand")
    @contact = Contact.create!(brand: @brand, name: "Alice", email: "alice@example.com")
    @other = Contact.create!(brand: @other_brand, name: "Other", phone: "+12025550123")
    @input = { name: "Bob", email: "bob@example.com", phone: "+12025550124",
               setup: { alert_no_inventory: true, alert_price_change: false } }
  end

  test "anonymous callers cannot list create or edit contacts" do
    get "/api/contacts"
    assert_response :unauthorized
    assert_no_difference "Contact.count" do
      post "/api/contacts", params: { contact: @input }, as: :json
      assert_response :unauthorized
    end
    patch "/api/contacts/#{@contact.id}", params: { contact: { name: "Changed" } }, as: :json
    assert_response :unauthorized
    assert_equal "Alice", @contact.reload.name
  end

  test "list and writes are scoped and only expose explicit fields" do
    sign_in
    get "/api/contacts"
    assert_response :success
    assert_equal [@contact.id], response.parsed_body["contacts"].map { |contact| contact["id"] }
    assert_equal %w[email id name phone setup], response.parsed_body["contacts"].first.keys.sort
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_difference "Contact.count", 1 do
      post "/api/contacts", params: { contact: @input.merge(brand_id: @other_brand.id) }, as: :json
      assert_response :created
    end
    created = Contact.find(response.parsed_body.dig("contact", "id"))
    assert_equal @brand.id, created.brand_id
    assert created.subscribed_to?("alert_no_inventory")
    assert_not created.subscribed_to?("alert_price_change")
    patch "/api/contacts/#{created.id}", params: { contact: { email: "", phone: "+12025550999", setup: { alert_no_inventory: false, alert_price_change: true }, brand_id: @other_brand.id } }, as: :json
    assert_response :success
    assert_nil created.reload.email
    assert_equal @brand.id, created.brand_id
    assert_not created.subscribed_to?("alert_no_inventory")
    assert created.subscribed_to?("alert_price_change")
  end

  test "show supports dialog deep links and enforces brand scope" do
    get "/api/contacts/#{@contact.id}"
    assert_response :unauthorized
    sign_in
    get "/api/contacts/#{@contact.id}"
    assert_response :success
    assert_equal @contact.name, response.parsed_body.dig("contact", "name")
    [@other.id, 99999999].each do |id|
      get "/api/contacts/#{id}"
      assert_response :not_found
    end
  end

  test "other brand and missing ids are concealed" do
    sign_in
    [@other.id, 999999999].each do |id|
      patch "/api/contacts/#{id}", params: { contact: { name: "Changed" } }, as: :json
      assert_response :not_found
    end
    assert_equal "Other", @other.reload.name
  end

  test "invalid data and malformed preference types produce errors without writes" do
    sign_in
    [@input.merge(name: ""), @input.merge(email: nil, phone: nil), @input.merge(email: "invalid"),
     @input.merge(phone: "123"), @input.merge(name: []), @input.merge(setup: "yes"),
     @input.merge(setup: { alert_no_inventory: "false", alert_price_change: true }),
     @input.merge(setup: { alert_no_inventory: true }), []].each do |input|
      assert_no_difference "Contact.count" do
        post "/api/contacts", params: { contact: input }, as: :json
        assert_response :unprocessable_entity
        assert response.parsed_body["error"].present?
      end
    end
    patch "/api/contacts/#{@contact.id}", params: { contact: { name: "" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "Alice", @contact.reload.name
  end

  test "collections are bounded ordered and validate pages" do
    sign_in
    21.times { |i| Contact.create!(brand: @brand, name: "Contact #{i}", email: "test@example.com") }
    get "/api/contacts"
    assert_equal 20, response.parsed_body["contacts"].length
    assert_equal 22, response.parsed_body.dig("pagination", "total")
    ids = response.parsed_body["contacts"].map { |contact| contact["id"] }
    assert_equal ids.sort.reverse, ids
    get "/api/contacts", params: { page: 2 }
    assert_equal 2, response.parsed_body["contacts"].length
    [0, -1, "abc", "1x", "1000000"].each do |page|
      get "/api/contacts", params: { page: page }
      assert_response :unprocessable_entity
    end
  end

  test "both write endpoints enforce csrf" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/api/session"
    token = response.parsed_body["csrf_token"]
    post "/api/session", params: { name: @brand.name }, headers: { "X-CSRF-Token" => token }, as: :json
    token = response.parsed_body["csrf_token"]
    post "/api/contacts", params: { contact: @input }, as: :json
    assert_response :unprocessable_entity
    patch "/api/contacts/#{@contact.id}", params: { contact: { name: "Changed" } }, as: :json
    assert_response :unprocessable_entity
    post "/api/contacts", params: { contact: @input }, headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :created
    patch "/api/contacts/#{@contact.id}", params: { contact: { name: "Changed" } }, headers: { "X-CSRF-Token" => token }, as: :json
    assert_response :success
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "keyword search matches name email or phone within the current brand" do
    @contact.update!(phone: "+13125550199")
    post "/api/session", params: { name: @brand.name }, as: :json
    ["  ALI  ", "EXAMPLE.COM", "5550199"].each do |keyword|
      get "/api/contacts", params: { q: keyword }
      assert_response :success
      assert_equal [@contact.id], response.parsed_body["contacts"].map { |c| c["id"] }
      assert_equal 1, response.parsed_body.dig("pagination", "total")
    end
    get "/api/contacts", params: { q: @other.phone }
    assert_empty response.parsed_body["contacts"]
    assert_equal 0, response.parsed_body.dig("pagination", "total")
  end

  test "search escapes wildcard characters and validates keyword input" do
    literal = Contact.create!(brand: @brand, name: "100%_literal", email: "literal@example.com")
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/contacts", params: { q: "%_" }
    assert_equal [literal.id], response.parsed_body["contacts"].map { |c| c["id"] }
    get "/api/contacts", params: { q: "' OR 1=1 --" }
    assert_empty response.parsed_body["contacts"]
    [["Alice"], { name: "Alice" }, "a" * 201].each do |keyword|
      get "/api/contacts", params: { q: keyword }
      assert_response :unprocessable_entity
    end
  end

  test "search paginates the filtered collection and whitespace clears the filter" do
    21.times { |i| Contact.create!(brand: @brand, name: "Match #{i}", email: "match#{i}@example.com") }
    post "/api/session", params: { name: @brand.name }, as: :json
    get "/api/contacts", params: { q: "Match", page: 2 }
    assert_equal 1, response.parsed_body["contacts"].length
    assert_equal 21, response.parsed_body.dig("pagination", "total")
    assert_equal 2, response.parsed_body.dig("pagination", "pages")
    get "/api/contacts", params: { q: "  " }
    assert_equal 22, response.parsed_body.dig("pagination", "total")
  end

  private

  def sign_in
    post "/api/session", params: { name: @brand.name }, as: :json
    assert_response :success
  end
end
