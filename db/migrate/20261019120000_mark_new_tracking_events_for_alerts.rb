class MarkNewTrackingEventsForAlerts < ActiveRecord::Migration[7.1]
  def up
    # PostgreSQL uses a constant default without rewriting the existing table.
    # Existing observations remain false; only subsequent inserts default to true.
    add_column :tracking_events, :alert_eligible, :boolean, null: false, default: false
    change_column_default :tracking_events, :alert_eligible, from: false, to: true
  end

  def down
    remove_column :tracking_events, :alert_eligible
  end
end
