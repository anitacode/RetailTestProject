class IndexLatestTrackingObservations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :tracking_events, [:store_id, :product_id, :event_type, :event_time, :id],
              order: { event_time: :desc, id: :desc },
              name: "index_tracking_events_on_latest_observation", algorithm: :concurrently
  end
end
