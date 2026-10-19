class Contact < ApplicationRecord
  belongs_to :brand
  has_many :notification_deliveries, dependent: :delete_all

  ALERT_TYPES = %w[alert_no_inventory alert_price_change].freeze
  before_validation :normalize_fields
  validates :name, presence: true
  validates :email, format: { with: /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/ }, allow_nil: true
  validates :phone, format: { with: /\A\+[1-9][0-9]{7,14}\z/ }, allow_nil: true
  validate :channel_available
  validate :valid_setup

  def subscribed_to?(kind)
    setup.is_a?(Hash) && setup[kind] == true
  end

  private

  def normalize_fields
    self.name = name&.strip
    self.email = email&.strip.presence
    self.phone = phone&.strip.presence
  end

  def channel_available
    errors.add(:base, "Provide an email or phone number") if email.blank? && phone.blank?
  end

  def valid_setup
    unless setup.is_a?(Hash) && setup.keys.sort == ALERT_TYPES.sort && setup.values.all? { |value| value == true || value == false }
      errors.add(:setup, "must contain only alert_no_inventory and alert_price_change, both booleans")
    end
  end
end
