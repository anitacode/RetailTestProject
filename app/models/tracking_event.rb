class TrackingEvent < ApplicationRecord
  enum :event_type, {
    inventory_presence: "inventory_presence",
    price_tracker: "price_tracker"
  }

  belongs_to :product
  belongs_to :store

  validate :payload_matches_event_type

  scope :latest_observation_first, -> { where.not(event_time: nil).reorder(event_time: :desc, id: :desc) }

  def self.latest_inventory(store_id:, product_id:)
    inventory_presence.where(store_id: store_id, product_id: product_id).latest_observation_first.first
  end

  def self.latest_price(store_id:, product_id:)
    price_tracker.where(store_id: store_id, product_id: product_id).latest_observation_first.first
  end

  def in_stock?
    inventory_presence? && value.fetch("quantity") > 0
  end

  private

  def payload_matches_event_type
    unless value.is_a?(Hash)
      errors.add(:value, "must be an object")
      return
    end

    if inventory_presence?
      quantity = value["quantity"]
      whole_number = (quantity.is_a?(Integer) || quantity.is_a?(Float) || quantity.is_a?(BigDecimal)) &&
        quantity.finite? && quantity == quantity.to_i
      errors.add(:value, "must include a finite whole-number quantity") unless whole_number
      errors.add(:value, "must not include present; stock status is derived from quantity") if value.key?("present")
    elsif price_tracker?
      amount = value["amount"]
      unless (amount.is_a?(Integer) || amount.is_a?(Float) || amount.is_a?(BigDecimal)) && amount.finite? && amount >= 0
        errors.add(:value, "must include a finite nonnegative numeric amount")
      end
      unless value["currency"].is_a?(String) && value["currency"].match?(/\A[A-Z]{3}\z/)
        errors.add(:value, "must include a three-letter uppercase currency code")
      end
    end
  end
end
