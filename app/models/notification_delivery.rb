class NotificationDelivery < ApplicationRecord
  belongs_to :contact
  belongs_to :alert, optional: true
  belongs_to :tracking_event, optional: true
end
