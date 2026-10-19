require "test_helper"

class ContactTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  parallelize(workers: 1)

  setup { @brand = Brand.create!(name: "Contact brand") }

  test "default preferences are opt out and either channel is sufficient" do
    contact = @brand.contacts.create!(name: " Alice ", email: " alice@example.com ")
    assert_equal "Alice", contact.name
    assert_equal "alice@example.com", contact.email
    assert_equal({ "alert_no_inventory" => false, "alert_price_change" => false }, contact.setup)
    assert @brand.contacts.new(name: "Bob", phone: "+12025550124").valid?
  end

  test "setup must have exactly the two boolean preferences" do
    [nil, [], {}, { alert_no_inventory: "true", alert_price_change: false },
     { alert_no_inventory: true, alert_price_change: false, extra: true }].each do |setup|
      contact = @brand.contacts.new(name: "Alice", email: "alice@example.com", setup: setup)
      assert_not contact.valid?
      assert contact.errors[:setup].present?
    end
  end

  test "invalid channel and missing destination are rejected" do
    [{}, { phone: "123" }, { email: "invalid" }].each do |channels|
      assert_not @brand.contacts.new(name: "Alice", **channels).valid?
    end
  end

  test "bulk writes cannot bypass JSON boolean and channel constraints" do
    [{ setup: { alert_no_inventory: "yes", alert_price_change: false } },
     { setup: {} }, { email: nil, phone: nil }, { phone: "invalid" }].each do |invalid|
      assert_raises(ActiveRecord::StatementInvalid) do
        Contact.transaction(requires_new: true) do
          Contact.insert_all!([{ brand_id: @brand.id, name: "Alice", email: "alice@example.com",
                                 setup: { alert_no_inventory: true, alert_price_change: false }, **invalid }])
        end
      end
    end
  end
end
