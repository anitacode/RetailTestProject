class EnablePriceInboxAlerts < ActiveRecord::Migration[7.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :alerts, :alert_type, :string, null: false, default: "alert_no_inventory"
    add_check_constraint :alerts, "alert_type IN ('alert_no_inventory', 'alert_price_change')",
                         name: "alerts_valid_type"

    # PostgreSQL constant defaults avoid rewriting existing tracking rows.
    # Existing prices may be baselines, but cannot trigger inbox alerts.
    add_column :tracking_events, :price_alert_eligible, :boolean, null: false, default: false
    change_column_default :tracking_events, :price_alert_eligible, from: false, to: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Removing alert types would mislabel stored price alerts as inventory alerts"
  end
end
