module Notifications
  class DispatchJob < ApplicationJob
    queue_as :notifications
    retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 3.seconds, attempts: 3

    def perform(kind, source_id)
      message = Message.for(kind, source_id)
      return unless message

      brand_id = message.first
      Contact.where(brand_id: brand_id).where("setup @> ?::jsonb", { kind => true }.to_json).find_each do |contact|
        DeliverJob.perform_later(kind, source_id, contact.id, "sms") if contact.phone.present?
        DeliverJob.perform_later(kind, source_id, contact.id, "email") if contact.email.present?
      end
    end
  end
end
