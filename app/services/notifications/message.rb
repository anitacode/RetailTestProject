module Notifications
  class Message
    def self.for(kind, source_id)
      case kind
      when "alert_no_inventory"
        alert = Alert.includes(:brand, :product, :store).find_by(id: source_id)
        return unless alert

        [alert.brand_id, "#{alert.brand.name}: #{alert.product.name} was out of stock in two consecutive checks at #{alert.store.address}. Alert ##{alert.id}.", { alert_id: alert.id }]
      when "alert_price_change"
        event = TrackingEvent.price_tracker.includes(product: :brand).includes(:store).find_by(id: source_id, alert_eligible: true)
        return unless event&.event_time

        previous = TrackingEvent.price_tracker.where(store_id: event.store_id, product_id: event.product_id, alert_eligible: true)
                                .where("event_time < :time OR (event_time = :time AND id < :id)", time: event.event_time, id: event.id)
                                .order(event_time: :desc, id: :desc).first
        return unless previous && previous.value["currency"] == event.value["currency"]
        return if previous.value["amount"] == event.value["amount"]

        [event.product.brand_id, "#{event.product.brand.name}: #{event.product.name} price changed from #{previous.value['amount']} to #{event.value['amount']} #{event.value['currency']} at #{event.store.address}.", { tracking_event_id: event.id }]
      end
    end
  end
end
