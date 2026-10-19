module Alerts
  class Reconcile
    # A single transaction-level lock coordinates reconciliation from concurrent
    # application writers. No email or other external side effect happens here.
    LOCK_ID = 731_904_219

    def self.call(store_id: nil, product_id: nil)
      Alert.transaction do
        Alert.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_ID})")
        reconcile_type("alert_no_inventory", store_id: store_id, product_id: product_id)
        reconcile_type("alert_price_change", store_id: store_id, product_id: product_id)
      end
    end

    def self.reconcile_type(kind, store_id:, product_id:)
      inventory = kind == "alert_no_inventory"
      source = TrackingEvent.where(event_type: inventory ? "inventory_presence" : "price_tracker")
                            .where(alert_eligible: true).where.not(event_time: nil)
      existing = Alert.where(alert_type: kind)
      if store_id && product_id
        source = source.where(store_id: store_id, product_id: product_id)
        existing = existing.where(store_id: store_id, product_id: product_id)
      end
      source_sql = source.select(:id, :store_id, :product_id, :event_time, :price_alert_eligible,
                                 Arel.sql("(value ->> '#{inventory ? 'quantity' : 'amount'}')::numeric AS amount"),
                                 Arel.sql("value ->> 'currency' AS currency")).to_sql
      condition = inventory ? "amount <= 0 AND previous_amount <= 0" :
                    "price_alert_eligible AND amount <> previous_amount AND currency = previous_currency"

      connection = Alert.connection
      # LAG sees only dated events of this category. A late observation may both add
      # qualifying pairs and invalidate pairs previously considered adjacent.
      inserted = connection.exec_query(<<~SQL)
        WITH ordered AS (
          SELECT *,
            LAG(id) OVER chronology AS previous_event_id,
            LAG(amount) OVER chronology AS previous_amount,
            LAG(currency) OVER chronology AS previous_currency
          FROM (#{source_sql}) AS observations
          WINDOW chronology AS (PARTITION BY store_id, product_id ORDER BY event_time, id)
        ), candidates AS (
          SELECT ordered.*, products.brand_id
          FROM ordered JOIN products ON products.id = ordered.product_id
          WHERE #{condition}
        ), removed AS (
          DELETE FROM alerts
          WHERE id IN (#{existing.select(:id).to_sql})
            AND NOT EXISTS (SELECT 1 FROM candidates WHERE candidates.id = alerts.triggering_event_id)
        ), updated AS (
          UPDATE alerts SET brand_id = candidates.brand_id,
            previous_event_id = candidates.previous_event_id,
            observed_at = candidates.event_time, updated_at = CURRENT_TIMESTAMP
          FROM candidates WHERE alerts.triggering_event_id = candidates.id
            AND (alerts.previous_event_id <> candidates.previous_event_id
              OR alerts.brand_id <> candidates.brand_id
              OR alerts.observed_at <> candidates.event_time)
        )
        INSERT INTO alerts (brand_id, store_id, product_id, previous_event_id,
          triggering_event_id, observed_at, alert_type, created_at, updated_at)
        SELECT brand_id, store_id, product_id, previous_event_id, id,
          event_time, #{connection.quote(kind)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM candidates
        ON CONFLICT (triggering_event_id) DO NOTHING
        RETURNING id
      SQL
      inserted.rows.each { |(id)| Notifications::DispatchJob.perform_later(kind, id) } if inventory
    end
    private_class_method :reconcile_type
  end
end
