class Alert < ApplicationRecord
  belongs_to :brand
  belongs_to :store
  belongs_to :product
  belongs_to :previous_event, class_name: "TrackingEvent"
  belongs_to :triggering_event, class_name: "TrackingEvent"

  validates :alert_type, inclusion: { in: %w[alert_no_inventory alert_price_change] }

  scope :unseen, -> { where(seen_at: nil) }

  def mark_seen!
    # Conditional SQL preserves the first visit even for concurrent requests.
    self.class.where(id: id, seen_at: nil).update_all(seen_at: Time.current, updated_at: Time.current)
    reload
  end

  scope :newest_first, -> { order(observed_at: :desc, id: :desc) }
end
