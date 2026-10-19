module Alerts
  class ReconcileJob < ApplicationJob
    queue_as :alerts
    retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 3.seconds, attempts: 3

    def perform(store_id: nil, product_id: nil)
      Reconcile.call(store_id: store_id, product_id: product_id)
    end
  end
end
