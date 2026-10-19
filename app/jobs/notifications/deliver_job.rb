module Notifications
  class DeliverJob < ApplicationJob
    queue_as :notifications
    retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 3.seconds, attempts: 3

    def perform(kind, source_id, contact_id, channel)
      return unless %w[sms email].include?(channel)

      delivery = NotificationDelivery.transaction do
        # Use the same lock as alert reconciliation and serialize duplicate deliveries.
        NotificationDelivery.connection.execute("SELECT pg_advisory_xact_lock(#{Alerts::Reconcile::LOCK_ID})")
        message = Message.for(kind, source_id)
        next unless message

        brand_id, body, source = message
        contact = Contact.lock.find_by(id: contact_id, brand_id: brand_id)
        next unless contact&.subscribed_to?(kind)

        destination = channel == "sms" ? contact.phone : contact.email
        next if destination.blank?
        next if NotificationDelivery.exists?(**source, contact_id: contact.id, channel: channel)

        NotificationDelivery.create!(**source, contact: contact, kind: kind, channel: channel,
                                               destination: destination, body: body, simulated_at: Time.current)
      end
      return unless delivery

      text = "[#{delivery.channel.upcase} SIMULATED] to=#{delivery.destination} #{delivery.body} (no real message sent)"
      Rails.logger.info(text)
      $stdout.puts(text)
    end
  end
end
