module Alerts
  # Compatibility for jobs already persisted under the original demo job name.
  # All delivery now uses the brand's opted-in contacts, never a fixed number.
  class SimulateSmsJob < ApplicationJob
    queue_as :notifications

    def perform(alert_id)
      Notifications::DispatchJob.perform_later("alert_no_inventory", alert_id)
    end
  end
end
